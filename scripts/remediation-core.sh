#!/usr/bin/env bash
set -euo pipefail

sanitize_token() {
  local raw_value="${1-}"
  local default_value="${2:?default value required}"
  local cleaned

  cleaned="$(printf '%s' "${raw_value:-$default_value}" | tr '[:upper:]' '[:lower:]' | tr -d '\r\n[:space:]')"
  case "$cleaned" in
    \"*\") cleaned="${cleaned#\"}"; cleaned="${cleaned%\"}" ;;
    \'*\') cleaned="${cleaned#\'}"; cleaned="${cleaned%\'}" ;;
  esac
  printf '%s\n' "$cleaned"
}

sanitize_positive_int() {
  local raw_value="${1-}"
  local default_value="${2:?default value required}"
  local name="${3:?name required}"
  local cleaned

  cleaned="$(sanitize_token "$raw_value" "$default_value")"
  if ! printf '%s' "$cleaned" | grep -Eq '^[0-9]+$' || [ "${cleaned:-0}" -lt 1 ]; then
    echo "${name} was invalid; defaulting to ${default_value}." >&2
    printf '%s\n' "$default_value"
    return 0
  fi
  printf '%s\n' "$cleaned"
}

run_with_timeout() {
  local timeout_sec="${1:?timeout seconds required}"
  shift

  if command -v timeout >/dev/null 2>&1; then
    timeout --kill-after=30s "${timeout_sec}s" "$@"
    return $?
  fi

  python3 - "$timeout_sec" "$@" <<'PY'
import subprocess
import sys

timeout_s = int(sys.argv[1])
cmd = sys.argv[2:]
try:
    raise SystemExit(subprocess.run(cmd, check=False, timeout=timeout_s).returncode)
except subprocess.TimeoutExpired:
    print(f"command timed out after {timeout_s}s: {' '.join(cmd)}", file=sys.stderr)
    raise SystemExit(124)
PY
}

agent_timeout_sec="$(sanitize_positive_int "${REACHABLE_AGENT_TIMEOUT_SEC-}" 1800 REACHABLE_AGENT_TIMEOUT_SEC)"
max_batches="$(sanitize_positive_int "${REACHABLE_MAX_BATCHES-}" 3 REACHABLE_MAX_BATCHES)"
rescan_strategy="$(sanitize_token "${REACHABLE_RESCAN_STRATEGY-}" each_batch)"
signal_types="$(sanitize_token "${REACHABLE_SIGNAL_TYPES-}" all)"
profile="$(sanitize_token "${REACHABLE_PROMPT_PROFILE-}" balanced)"
branch="${REACHABLE_REMEDIATION_BRANCH:?REACHABLE_REMEDIATION_BRANCH is required}"
agent_runner="${REACHABLE_AGENT_RUNNER:-./scripts/run-agent.sh}"
stage_paths_py="${REACHABLE_STAGE_PATHS_PY:-./scripts/stage-paths.py}"
outputs_path="${REACHABLE_CORE_OUTPUTS_PATH:-}"
proof_commit="$(git rev-parse HEAD)"
remediation_committed="false"

case "$rescan_strategy" in
  each_batch|final_only) ;;
  *)
    echo "REACHABLE_RESCAN_STRATEGY must be each_batch or final_only." >&2
    exit 2
    ;;
esac

signal_args=()
if [ "$signal_types" = "all" ]; then
  signal_args+=(--all)
else
  IFS=',' read -ra families <<< "$signal_types"
  for family in "${families[@]}"; do
    family="$(echo "$family" | xargs)"
    [ -n "$family" ] && signal_args+=(--signal-type "$family")
  done
fi

run_project_tests() {
  if [ "${REACHABLE_RUN_PROJECT_TESTS:-false}" != "true" ]; then
    return 0
  fi
  if [ -n "${REACHABLE_PROJECT_TEST_COMMAND:-}" ]; then
    bash -lc "$REACHABLE_PROJECT_TEST_COMMAND"
    return 0
  fi
  case "${REACHABLE_TEST_PRESET:-none}" in
    none) echo "Project tests disabled: test_preset=none." ;;
    go) go test ./... ;;
    python-pytest) python -m pytest ;;
    python-unittest) python -m unittest ;;
    maven) mvn test ;;
    gradle) gradle test ;;
    npm) npm test ;;
    pnpm) pnpm test ;;
    yarn) yarn test ;;
    rust) cargo test ;;
    dotnet) dotnet test ;;
    ruby-rspec) bundle exec rspec ;;
    phpunit) vendor/bin/phpunit ;;
    swift) xcodebuild test ;;
    elixir) mix test ;;
    *)
      echo "Unsupported test configuration. Set REACHABLE_PROJECT_TEST_COMMAND or a supported REACHABLE_TEST_PRESET." >&2
      exit 2
      ;;
  esac
}

write_outputs() {
  if [ -n "$outputs_path" ]; then
    {
      echo "REACHABLE_PROOF_COMMIT=$proof_commit"
      echo "REACHABLE_REMEDIATION_COMMITTED=$remediation_committed"
    } > "$outputs_path"
  fi
}

for batch in $(seq 1 "$max_batches"); do
  echo "== Reachable remediation batch ${batch}/${max_batches} =="
  echo "Reachable agent timeout for this batch: ${agent_timeout_sec}s"
  rm -rf .reachable/remediation-bundle

  reachctl remediate . \
    --context ci \
    --agent "${REACHABLE_AGENT}" \
    --mode branch \
    --branch-name "$branch" \
    --profile "$profile" \
    "${signal_args[@]}"

  if [ ! -f .reachable/remediation-bundle/prompt.md ]; then
    echo "No remediation bundle was produced; stopping batch loop."
    break
  fi

  run_with_timeout "$agent_timeout_sec" \
    "$agent_runner" "${REACHABLE_AGENT}" .reachable/remediation-bundle/prompt.md

  reachctl remediate . --cleanup || true
  run_project_tests

  if [ "$rescan_strategy" = "each_batch" ]; then
    reachctl scan . --ci --branch "$branch" --commit "$(git rev-parse HEAD)"
  fi
done

stage_list="$(mktemp)"
candidate_list="$(mktemp)"
git ls-files --modified --others --exclude-standard -z > "$candidate_list"
python3 "$stage_paths_py" "$candidate_list" "$stage_list"
rm -f "$candidate_list"

if [ ! -s "$stage_list" ]; then
  rm -f "$stage_list"
  echo "No remediation changes to commit."
  write_outputs
  exit 0
fi

git add --pathspec-from-file="$stage_list" --pathspec-file-nul
rm -f "$stage_list"
if git diff --cached --quiet; then
  echo "No remediation changes to commit."
  write_outputs
  exit 0
fi

git commit -m "fix: reachable remediation"
remediation_committed="true"
proof_commit="$(git rev-parse HEAD)"
write_outputs
