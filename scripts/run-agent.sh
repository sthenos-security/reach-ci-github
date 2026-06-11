#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/run-agent.sh AGENT PROMPT_PATH

Supported AGENT values:
  claude    Run Claude Code non-interactively.
  codex     Run Codex CLI non-interactively.

The script is intentionally thin. Reachable owns scan, bundle generation,
audit artifacts, and proof. The selected coding agent only consumes prompt.md
and edits the current branch.
EOF
}

if [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

agent_input="${1:-${REACHABLE_AGENT_NAME:-}}"
prompt_input="${2:-${REACHABLE_AGENT_PROMPT_PATH:-}}"

if [ -z "$agent_input" ] || [ -z "$prompt_input" ]; then
  usage
  exit 2
fi

AGENT="$(printf '%s' "$agent_input" | tr '[:upper:]' '[:lower:]')"
PROMPT_PATH="$prompt_input"

if [ ! -f "$PROMPT_PATH" ]; then
  echo "prompt file not found: $PROMPT_PATH" >&2
  exit 2
fi

case "$AGENT" in
  claude)
    command -v claude >/dev/null 2>&1 || {
      echo "claude CLI not found. Install Claude Code or select another agent." >&2
      exit 127
    }
    claude_args=()
    if [ -n "${REACHABLE_AGENT_MODEL:-}" ]; then
      claude_args+=(--model "${REACHABLE_AGENT_MODEL}")
    fi
    claude_args+=(
      --permission-mode bypassPermissions
      --no-session-persistence
      --verbose
      --output-format stream-json
      --max-budget-usd "${CLAUDE_MAX_BUDGET_USD:-5}"
    )
    claude "${claude_args[@]}" -p "Apply the Reachable remediation task provided on stdin to this repository. Treat stdin as the authoritative instructions, make the requested changes, and stop when the task is complete." < "$PROMPT_PATH"
    ;;

  codex)
    command -v codex >/dev/null 2>&1 || {
      echo "codex CLI not found. Install Codex or select another agent." >&2
      exit 127
    }
    codex_args=(
      --dangerously-bypass-approvals-and-sandbox
      --skip-git-repo-check
    )
    if [ -n "${REACHABLE_AGENT_MODEL:-}" ]; then
      codex_args=(--model "${REACHABLE_AGENT_MODEL}" "${codex_args[@]}")
    fi
    codex exec "${codex_args[@]}" < "$PROMPT_PATH"
    ;;

  *)
    echo "unsupported agent: $AGENT" >&2
    usage
    exit 2
    ;;
esac
