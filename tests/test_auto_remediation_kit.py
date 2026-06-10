from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = (ROOT / ".github" / "workflows" / "auto-remediate.yml").read_text(encoding="utf-8")
VALIDATOR = (ROOT / "scripts" / "validate-workflows.py").read_text(encoding="utf-8")


class WorkflowContractTests(unittest.TestCase):
    def test_publish_report_skips_when_reachable_setup_never_happened(self) -> None:
        self.assertIn('if ! command -v reachctl >/dev/null 2>&1; then', WORKFLOW)
        self.assertIn('echo "Reachable CLI is unavailable; skipping report publication."', WORKFLOW)
        self.assertIn('if ! python -c "import reachable.ci.proof_page" >/dev/null 2>&1; then', WORKFLOW)
        self.assertIn('echo "Reachable Python package is unavailable; skipping report publication."', WORKFLOW)

    def test_claude_lane_uses_non_interactive_prompt_with_stdin(self) -> None:
        self.assertIn("--permission-mode bypassPermissions", WORKFLOW)
        self.assertIn("--no-session-persistence", WORKFLOW)
        self.assertIn("--verbose", WORKFLOW)
        self.assertIn("--output-format stream-json", WORKFLOW)
        self.assertIn("Apply the Reachable remediation task provided on stdin", WORKFLOW)
        self.assertIn('claude "${claude_args[@]}" -p "Apply the Reachable remediation task provided on stdin to this repository.', WORKFLOW)
        self.assertNotIn('claude "${claude_args[@]}" < .reachable/remediation-bundle/prompt.md', WORKFLOW)
        self.assertNotIn("                  --print\n", WORKFLOW)

    def test_validator_tracks_publish_and_claude_contracts(self) -> None:
        self.assertIn("Reachable Python package is unavailable; skipping report publication.", VALIDATOR)
        self.assertIn("Apply the Reachable remediation task provided on stdin", VALIDATOR)
        self.assertIn("claude remediation lane must pass an explicit non-interactive prompt with -p", VALIDATOR)


if __name__ == "__main__":
    unittest.main()
