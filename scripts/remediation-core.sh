#!/usr/bin/env bash
set -euo pipefail

agent_timeout_sec="$(printf '%s' "${REACHABLE_AGENT_TIMEOUT_SEC:-900}" | tr -d '\r\n[:space:]')"
max_batches="$(printf '%s' "${REACHABLE_MAX_BATCHES:-3}" | tr -d '\r\n[:space:]')"
rescan_strategy="${REACHABLE_RESCAN_STRATEGY:-each_batch}"
signal_types="${REACHABLE_SIGNAL_TYPES:-all}"
profile="${REACHABLE_PROMPT_PROFILE:-balanced}"
branch="${REACHABLE_REMEDIATION_BRANCH:?REACHABLE_REMEDIATION_BRANCH is required}"
agent_runner="${REACHABLE_AGENT_RUNNER:-./scripts/run-agent.sh}"
stage_paths_py="${REACHABLE_STAGE_PATHS_PY:-./scripts/stage-paths.py}"
outputs_path="${REACHABLE_CORE_OUTPUTS_PATH:-}"
proof_commit="$(git rev-parse HEAD)"
remediation_committed="false"

if ! printf '%s' "$agent_timeout_sec" | grep -Eq '^[0-9]+$' || [ "$agent_timeout_sec" -lt 1 ]; then
  echo "REACHABLE_AGENT_TIMEOUT_SEC must be a positive integer number of seconds." >&2
  exit 2
fi
if ! printf '%s' "$max_batches" | grep -Eq '^[0-9]+$' || [ "$max_batches" -lt 1 ]; then
  echo "REACHABLE_MAX_BATCHES must be a positive integer." >&2
  exit 2
fi
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

  timeout --kill-after=30s "${agent_timeout_sec}s" \
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
