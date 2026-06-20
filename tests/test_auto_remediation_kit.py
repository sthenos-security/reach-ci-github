from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ROOT_ACTION = (ROOT / "action.yml").read_text(encoding="utf-8")
WORKFLOW = (ROOT / ".github" / "workflows" / "auto-remediate.yml").read_text(encoding="utf-8")
VALIDATOR = (ROOT / "scripts" / "validate-workflows.py").read_text(encoding="utf-8")
RUN_AGENT = (ROOT / "scripts" / "run-agent.sh").read_text(encoding="utf-8")
REMEDIATION_CORE = (ROOT / "scripts" / "remediation-core.sh").read_text(encoding="utf-8")


class WorkflowContractTests(unittest.TestCase):
    def test_mode_aliases_and_model_override_are_supported(self) -> None:
        self.assertIn("openai-codex openai-gpt anthropic-claude copilot-github", WORKFLOW)
        self.assertIn("ai_mode=openai-gpt is scan-only", WORKFLOW)
        self.assertIn("REACHABLE_PROOF_FAIL_ON", WORKFLOW)
        self.assertIn('if [ -z "${REACHABLE_AGENT_MODEL:-}" ]; then', WORKFLOW)
        self.assertIn('echo "REACHABLE_AGENT_MODEL=gpt-5.4-mini" >> "$GITHUB_ENV"', WORKFLOW)
        self.assertIn('echo "REACHABLE_AGENT_MODEL=claude-sonnet-4-5-20250929" >> "$GITHUB_ENV"', WORKFLOW)
        self.assertIn("--sarif .reachable/ci-artifacts/reachable-after-final.sarif", WORKFLOW)
        self.assertIn("openai-codex openai-gpt anthropic-claude copilot-github", ROOT_ACTION)
        self.assertIn("ai_mode=openai-gpt is scan-only", ROOT_ACTION)
        self.assertIn("openai_api_key", ROOT_ACTION)
        self.assertIn("anthropic_api_key", ROOT_ACTION)

    def test_copilot_lane_dispatches_async_tasks_without_local_agent_execution(self) -> None:
        for text in (WORKFLOW, ROOT_ACTION):
            self.assertIn("REACHABLE_COPILOT_USER_TOKEN", text)
            self.assertIn("ai_mode=copilot-github requires REACHABLE_COPILOT_USER_TOKEN for dispatch.", text)
            self.assertIn("reachctl copilot doctor --repo", text)
            self.assertIn("reachctl copilot dispatch", text)
            self.assertIn(".reachable/ci-artifacts/copilot-doctor.json", text)
            self.assertIn(".reachable/ci-artifacts/copilot-dispatch.json", text)
            self.assertIn("REACHABLE_REQUIRE_COPILOT_TASKS=true", text)
            self.assertIn("env.REACHABLE_AI_MODE != 'copilot-github'", text)
            self.assertIn("env.REACHABLE_AI_MODE == 'copilot-github'", text)
        self.assertIn("issues: write", WORKFLOW)
        self.assertNotIn("npm install -g @github/copilot", WORKFLOW)
        self.assertNotIn("npm install -g @github/copilot", ROOT_ACTION)

    def test_publish_report_skips_when_reachable_setup_never_happened(self) -> None:
        self.assertIn('if ! command -v reachctl >/dev/null 2>&1; then', WORKFLOW)
        self.assertIn('echo "Reachable CLI is unavailable; skipping report publication."', WORKFLOW)
        self.assertIn('if ! python -c "import reachable.ci.proof_page" >/dev/null 2>&1; then', WORKFLOW)
        self.assertIn('echo "Reachable Python package is unavailable; skipping report publication."', WORKFLOW)
        self.assertIn('if ! command -v reachctl >/dev/null 2>&1; then', ROOT_ACTION)
        self.assertIn('echo "Reachable CLI is unavailable; skipping report publication."', ROOT_ACTION)
        self.assertIn('if ! python -c "import reachable.ci.proof_page" >/dev/null 2>&1; then', ROOT_ACTION)
        self.assertIn('echo "Reachable Python package is unavailable; skipping report publication."', ROOT_ACTION)

    def test_publish_report_deploys_public_pages_when_proof_exists(self) -> None:
        self.assertIn("uses: actions/configure-pages@v6", WORKFLOW)
        self.assertIn("uses: actions/upload-pages-artifact@v5", WORKFLOW)
        self.assertIn("uses: actions/deploy-pages@v5", WORKFLOW)
        self.assertIn("hashFiles('.reachable/ci-artifacts/release-proof/index.html') != ''", WORKFLOW)
        self.assertIn("path: .reachable/ci-artifacts/release-proof", WORKFLOW)
        self.assertIn("uses: actions/configure-pages@v6", ROOT_ACTION)
        self.assertIn("uses: actions/upload-pages-artifact@v5", ROOT_ACTION)
        self.assertIn("uses: actions/deploy-pages@v5", ROOT_ACTION)
        self.assertIn("hashFiles('.reachable/ci-artifacts/release-proof/index.html') != ''", ROOT_ACTION)
        self.assertIn("path: .reachable/ci-artifacts/release-proof", ROOT_ACTION)

    def test_optional_exports_warn_instead_of_silent_true(self) -> None:
        self.assertIn("::warning title=Reachable JSON export unavailable::", WORKFLOW)
        self.assertIn("::warning title=Reachable summary export unavailable::", WORKFLOW)
        self.assertNotIn("reachable-report.json || true", WORKFLOW)
        self.assertNotIn("reachable-summary.txt || true", WORKFLOW)
        self.assertIn("::warning title=Reachable JSON export unavailable::", ROOT_ACTION)
        self.assertIn("::warning title=Reachable summary export unavailable::", ROOT_ACTION)

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
        self.assertIn("copilot-github", VALIDATOR)
        self.assertIn('run_with_timeout \\"$agent_timeout_sec\\"', VALIDATOR)
        self.assertIn("marketplace action contract ok", VALIDATOR)

    def test_setup_and_pr_actions_have_ci_fallbacks(self) -> None:
        setup = (ROOT / "actions" / "setup-reachable" / "action.yml").read_text(encoding="utf-8")
        pr_action = (ROOT / "actions" / "open-remediation-pr" / "action.yml").read_text(encoding="utf-8")
        self.assertIn("for attempt in 1 2 3", setup)
        self.assertIn("Reachable installer failed after", setup)
        self.assertIn("pr-created=false", pr_action)
        self.assertIn("GitHub rejected automatic PR creation", pr_action)
        self.assertIn("open a PR manually", pr_action)
        self.assertIn("grep -Eom1 '^https?://[^[:space:]]+$'", pr_action)
        self.assertNotIn("awk '/^https?:\\\\/\\\\// {print; exit}'", pr_action)

    def test_portable_timeout_wrapper_is_embedded_in_remediation_core(self) -> None:
        self.assertIn('run_with_timeout() {', REMEDIATION_CORE)
        self.assertIn('if command -v timeout >/dev/null 2>&1; then', REMEDIATION_CORE)
        self.assertIn('subprocess.run(cmd, check=False, timeout=timeout_s).returncode', REMEDIATION_CORE)
        self.assertIn('run_with_timeout "$agent_timeout_sec"', REMEDIATION_CORE)
        self.assertIn('--output-dir .reachable/remediation-bundle', REMEDIATION_CORE)
        self.assertIn('reachctl remediate . --output-dir .reachable/remediation-bundle --cleanup', REMEDIATION_CORE)

    def test_root_action_is_the_marketplace_entrypoint(self) -> None:
        self.assertIn("name: Reachable CI Auto Remediation", ROOT_ACTION)
        self.assertIn("branding:", ROOT_ACTION)
        self.assertIn("icon: shield", ROOT_ACTION)
        self.assertIn("color: red", ROOT_ACTION)
        self.assertIn("uses: ./actions/setup-reachable", ROOT_ACTION)
        self.assertIn("uses: ./actions/remediation-core", ROOT_ACTION)
        self.assertIn("uses: ./actions/open-remediation-pr", ROOT_ACTION)
        self.assertIn("Reachable CI Action requires a checked-out repository.", ROOT_ACTION)
        self.assertIn("upload_artifacts", ROOT_ACTION)
        self.assertIn("publish_pages", ROOT_ACTION)


if __name__ == "__main__":
    unittest.main()
