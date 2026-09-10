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
# Profile is owned by the installed reachctl (default balanced). Do not pass
# --profile from CI/CD.
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
# signal_types=all means "use reachctl default scope" (config default is all
# families). Do not pass --all: that flag only exists to override a narrowed
# config. Depth beyond defaults is --deep-remediation, not --all.
if [ "$signal_types" != "all" ]; then
  IFS=',' read -ra families <<< "$signal_types"
  for family in "${families[@]}"; do
    family="$(echo "$family" | xargs)"
    [ -n "$family" ] && signal_args+=(--signal-type "$family")
  done
fi

write_outputs() {
  if [ -n "$outputs_path" ]; then
    {
      echo "REACHABLE_PROOF_COMMIT=$proof_commit"
      echo "REACHABLE_REMEDIATION_COMMITTED=$remediation_committed"
    } > "$outputs_path"
  fi
}

bundle_log="${RUNNER_TEMP:-/tmp}/reachable-bundle-output.txt"
for batch in $(seq 1 "$max_batches"); do
  echo "== Reachable remediation batch ${batch}/${max_batches} =="
  echo "Reachable agent timeout for this batch: ${agent_timeout_sec}s"
  rm -rf .reachable/remediation-bundle

  # CI adapters need a deterministic workspace-local private handoff because
  # the selected coding agent reads prompt.md from the checked-out repository.
  # reachctl's default CI output stays in user-scoped transient state unless an
  # orchestrator opts into a path, so keep this explicit and clean the same path.
  reachctl remediate . \
    --context ci \
    --output-dir .reachable/remediation-bundle \
    --agent "${REACHABLE_AGENT}" \
    --mode branch \
    --branch-name "$branch" \
    "${signal_args[@]}" | tee "$bundle_log"

  if [ ! -f .reachable/remediation-bundle/prompt.md ]; then
    echo "No remediation bundle was produced; stopping batch loop."
    break
  fi

  # The prompt comes from the DATABASE, not from the file on disk.
  #
  # prompt.md is still written -- the bundle carries rules.json and ai-rules/
  # that other steps consume -- but it is EVIDENCE of what was composed, not the
  # input. Reading it back would reopen a window in which anything else running
  # in this job (a dependency's install hook, a compromised earlier step) can
  # rewrite the file between our write and the agent's read, while the agent is
  # instructed to treat it as authoritative.
  #
  # `--emit-prompt --run-id` recomposes from remediation.db with the same
  # composer the local path uses, so the text is byte-identical to what was
  # recorded, and nothing on disk sits between the two.
  run_id="$(sed -n 's/^ *run id: *//p' "$bundle_log" | tail -1)"
  if [ -z "$run_id" ]; then
    echo "remediate --context ci printed no run id; refusing to fall back to reading prompt.md from the workspace." >&2
    exit 1
  fi

  run_with_timeout "$agent_timeout_sec" \
    bash -c 'reachctl remediate . --emit-prompt --run-id "$1" | "$2" "$3" -' \
    _ "$run_id" "$agent_runner" "${REACHABLE_AGENT}"

  reachctl remediate . --output-dir .reachable/remediation-bundle --cleanup || true

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
