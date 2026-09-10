#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

repo="$tmpdir/repo"
bin_dir="$tmpdir/bin"
mkdir -p "$repo" "$bin_dir"

cat > "$bin_dir/reachctl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  remediate)
    output_dir=""
    cleanup=false
    emit_prompt=false
    run_id=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --output-dir)
          output_dir="${2:-}"
          shift 2
          ;;
        --cleanup)
          cleanup=true
          shift
          ;;
        --emit-prompt)
          emit_prompt=true
          shift
          ;;
        --run-id)
          run_id="${2:-}"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    if [[ "$emit_prompt" == "true" ]]; then
      # G1 contract: the prompt is recomposed from remediation.db by run id and
      # arrives on stdout. Refuse an id we never issued -- a fake that answers
      # any id would let the core pass while parsing the wrong line.
      if [[ "$run_id" != "fake-run-001" ]]; then
        echo "emit-prompt asked for unknown run id: $run_id" >&2
        exit 2
      fi
      printf 'fake remediation prompt recomposed from db\n'
      exit 0
    fi
    if [[ "$output_dir" != ".reachable/remediation-bundle" ]]; then
      echo "missing expected --output-dir .reachable/remediation-bundle" >&2
      exit 2
    fi
    if [[ "$cleanup" == "true" ]]; then
      rm -rf "$output_dir"
      exit 0
    fi
    mkdir -p "$output_dir/ai-rules"
    printf 'fake remediation prompt\n' > "$output_dir/prompt.md"
    printf '{"selected_rule_count":1,"selected_rules":[{"rule_id":"demo-rule"}]}\n' > "$output_dir/bundle.json"
    printf '{"rules":["demo-rule"]}\n' > "$output_dir/ai-rules/rules.json"
    # G1 contract: the bundle step announces the run id the core must hand back
    # to --emit-prompt; without this line the core refuses to proceed.
    printf 'run id: fake-run-001\n'
    ;;
  scan)
    mkdir -p .reachable/ci-artifacts
    printf '{"scan":"ok"}\n' > .reachable/ci-artifacts/fake-scan.json
    ;;
  *)
    echo "unexpected reachctl command: $*" >&2
    exit 2
    ;;
esac
SH
chmod +x "$bin_dir/reachctl"

cat > "$bin_dir/fake-agent.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
agent="${1:?agent required}"
prompt="${2:?prompt required}"
if [ "$prompt" = "-" ]; then
  # G1 contract: the prompt arrives on stdin, never as a workspace file.
  prompt_text="$(cat)"
  case "$prompt_text" in
    *"recomposed from db"*) ;;
    *)
      echo "agent runner got the wrong prompt on stdin: $prompt_text" >&2
      exit 1
      ;;
  esac
else
  test -f "$prompt"
fi
printf 'agent=%s\n' "$agent" > remediation.txt
SH
chmod +x "$bin_dir/fake-agent.sh"

cd "$repo"
git init -q
git config user.name "reachable-test"
git config user.email "reachable-test@example.com"
printf 'initial\n' > README.md
git add README.md
git commit -qm "initial"
git switch -c reachable-test -q

PATH="$bin_dir:$PATH" \
  REACHABLE_AGENT_TIMEOUT_SEC=' "not-a-number" ' \
  REACHABLE_MAX_BATCHES=' "1" ' \
  REACHABLE_RESCAN_STRATEGY=' "EACH_BATCH" ' \
  REACHABLE_SIGNAL_TYPES=' "ALL" ' \
  REACHABLE_PROMPT_PROFILE=' "BALANCED" ' \
  REACHABLE_REMEDIATION_BRANCH="reachable-test" \
  REACHABLE_AGENT="codex" \
  REACHABLE_AGENT_RUNNER="$bin_dir/fake-agent.sh" \
  REACHABLE_STAGE_PATHS_PY="$ROOT/scripts/stage-paths.py" \
  bash "$ROOT/scripts/remediation-core.sh" > "$tmpdir/core.out" 2> "$tmpdir/core.err"

grep -q "REACHABLE_AGENT_TIMEOUT_SEC was invalid; defaulting to 1800." "$tmpdir/core.err"
grep -q "Reachable agent timeout for this batch: 1800s" "$tmpdir/core.out"
test ! -e "$repo/.reachable/remediation-bundle/prompt.md"
test ! -e "$repo/.reachable/remediation-bundle/bundle.json"
git log --oneline -1 | grep -q "fix: reachable remediation"
git show --name-only --oneline -1 | grep -q "remediation.txt"

echo "remediation-core sanitizer smoke ok"
