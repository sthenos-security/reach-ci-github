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

# `-` means "the prompt is already on our stdin", which is how the caller pipes
# it straight from the database (`reachctl remediate --emit-prompt --run-id`)
# instead of materialising prompt.md in the checked-out repository. A file in the
# workspace can be rewritten by anything else running in the same CI job --
# including a dependency's install hook -- between the moment we write it and the
# moment the agent reads it, and the agent is told to treat it as authoritative.
# Piping removes the artifact rather than trying to protect it.
if [ "$PROMPT_PATH" = "-" ]; then
  PROMPT_FROM_STDIN=1
elif [ ! -f "$PROMPT_PATH" ]; then
  echo "prompt file not found: $PROMPT_PATH" >&2
  exit 2
else
  PROMPT_FROM_STDIN=0
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
    claude_wrapper="Apply the Reachable remediation task provided on stdin to this repository. Treat stdin as the authoritative instructions, make the requested changes, and stop when the task is complete."
    if [ "$PROMPT_FROM_STDIN" = "1" ]; then
      claude "${claude_args[@]}" -p "$claude_wrapper"
    else
      claude "${claude_args[@]}" -p "$claude_wrapper" < "$PROMPT_PATH"
    fi
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
    if [ "$PROMPT_FROM_STDIN" = "1" ]; then
      codex exec "${codex_args[@]}"
    else
      codex exec "${codex_args[@]}" < "$PROMPT_PATH"
    fi
    ;;

  *)
    echo "unsupported agent: $AGENT" >&2
    usage
    exit 2
    ;;
esac
