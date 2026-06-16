from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = (ROOT / ".github" / "workflows" / "auto-remediate.yml").read_text(encoding="utf-8")
VALIDATOR = (ROOT / "scripts" / "validate-workflows.py").read_text(encoding="utf-8")
RUN_AGENT = (ROOT / "scripts" / "run-agent.sh").read_text(encoding="utf-8")
REMEDIATION_CORE = (ROOT / "scripts" / "remediation-core.sh").read_text(encoding="utf-8")


class WorkflowContractTests(unittest.TestCase):
    def test_mode_aliases_and_model_override_are_supported(self) -> None:
        self.assertIn("openai-codex openai-gpt anthropic-claude", WORKFLOW)
        self.assertIn("ai_mode=openai-gpt is scan-only", WORKFLOW)
        self.assertIn("REACHABLE_PROOF_FAIL_ON", WORKFLOW)
        self.assertIn('if [ -z "${REACHABLE_AGENT_MODEL:-}" ]; then', WORKFLOW)
        self.assertIn('echo "REACHABLE_AGENT_MODEL=gpt-5.4-mini" >> "$GITHUB_ENV"', WORKFLOW)
        self.assertIn('echo "REACHABLE_AGENT_MODEL=claude-sonnet-4-5-20250929" >> "$GITHUB_ENV"', WORKFLOW)
        self.assertIn("--sarif .reachable/ci-artifacts/reachable-after-final.sarif", WORKFLOW)

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
        self.assertIn("ai_mode=openai-gpt is scan-only", VALIDATOR)
        self.assertIn('run_with_timeout \\"$agent_timeout_sec\\"', VALIDATOR)

    def test_setup_and_pr_actions_have_ci_fallbacks(self) -> None:
        setup = (ROOT / "actions" / "setup-reachable" / "action.yml").read_text(encoding="utf-8")
        pr_action = (ROOT / "actions" / "open-remediation-pr" / "action.yml").read_text(encoding="utf-8")
        self.assertIn("for attempt in 1 2 3", setup)
        self.assertIn("Reachable installer failed after", setup)
        self.assertIn("pr-created=false", pr_action)
        self.assertIn("GitHub rejected automatic PR creation", pr_action)
        self.assertIn("open a PR manually", pr_action)

    def test_portable_timeout_wrapper_is_embedded_in_remediation_core(self) -> None:
        self.assertIn('run_with_timeout() {', REMEDIATION_CORE)
        self.assertIn('if command -v timeout >/dev/null 2>&1; then', REMEDIATION_CORE)
        self.assertIn('subprocess.run(cmd, check=False, timeout=timeout_s).returncode', REMEDIATION_CORE)
        self.assertIn('run_with_timeout "$agent_timeout_sec"', REMEDIATION_CORE)
        self.assertIn('--output-dir .reachable/remediation-bundle', REMEDIATION_CORE)
        self.assertIn('reachctl remediate . --output-dir .reachable/remediation-bundle --cleanup', REMEDIATION_CORE)


if __name__ == "__main__":
    unittest.main()
