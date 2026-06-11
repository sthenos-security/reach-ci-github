from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = (ROOT / ".github" / "workflows" / "auto-remediate.yml").read_text(encoding="utf-8")
VALIDATOR = (ROOT / "scripts" / "validate-workflows.py").read_text(encoding="utf-8")
RUN_AGENT = (ROOT / "scripts" / "run-agent.sh").read_text(encoding="utf-8")


class WorkflowContractTests(unittest.TestCase):
    def test_mode_aliases_and_model_override_are_supported(self) -> None:
        self.assertIn("codex-openai|openai-codex|codex|openai", WORKFLOW)
        self.assertIn("claude-anthropic|anthropic-claude|claude|anthropic", WORKFLOW)
        self.assertIn('if [ -z "${REACHABLE_AGENT_MODEL:-}" ]; then', WORKFLOW)
        self.assertIn('echo "REACHABLE_AGENT_MODEL=gpt-5.4-mini" >> "$GITHUB_ENV"', WORKFLOW)
        self.assertIn('echo "REACHABLE_AGENT_MODEL=claude-sonnet-4-5-20250929" >> "$GITHUB_ENV"', WORKFLOW)

    def test_publish_report_skips_when_reachable_setup_never_happened(self) -> None:
        self.assertIn('if ! command -v reachctl >/dev/null 2>&1; then', WORKFLOW)
        self.assertIn('echo "Reachable CLI is unavailable; skipping report publication."', WORKFLOW)
        self.assertIn('if ! python -c "import reachable.ci.proof_page" >/dev/null 2>&1; then', WORKFLOW)
        self.assertIn('echo "Reachable Python package is unavailable; skipping report publication."', WORKFLOW)

    def test_claude_lane_uses_non_interactive_prompt_with_stdin(self) -> None:
        self.assertIn("--permission-mode bypassPermissions", RUN_AGENT)
        self.assertIn("--no-session-persistence", RUN_AGENT)
        self.assertIn("--verbose", RUN_AGENT)
        self.assertIn("--output-format stream-json", RUN_AGENT)
        self.assertIn("Apply the Reachable remediation task provided on stdin", RUN_AGENT)
        self.assertIn('claude "${claude_args[@]}" -p "Apply the Reachable remediation task provided on stdin to this repository.', RUN_AGENT)
        self.assertNotIn('claude "${claude_args[@]}" < .reachable/remediation-bundle/prompt.md', RUN_AGENT)
        self.assertNotIn("                  --print\n", RUN_AGENT)

    def test_validator_tracks_publish_and_claude_contracts(self) -> None:
        self.assertIn("Reachable Python package is unavailable; skipping report publication.", VALIDATOR)
        self.assertIn("Apply the Reachable remediation task provided on stdin", VALIDATOR)
        self.assertIn("claude-anthropic|anthropic-claude|claude|anthropic", VALIDATOR)


if __name__ == "__main__":
    unittest.main()
