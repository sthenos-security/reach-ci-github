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
        *)
          shift
          ;;
      esac
    done
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
test -f "$prompt"
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
