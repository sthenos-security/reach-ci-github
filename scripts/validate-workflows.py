#!/usr/bin/env python3
"""Validate the Reachable GitHub CI package.

This intentionally stays lightweight so it can run in a fresh checkout without
installing the Reachable wheel.
"""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PRIVATE_PATTERNS = (
    ".reachable/remediation-bundle/**",
    ".reachable/remediation-bundle",
    "prompt.md",
    "bundle.json",
    "rules.json",
    "private-agent-logs",
)


def _load_yaml(path: Path) -> dict | None:
    try:
        import yaml  # type: ignore[import-not-found]
    except ModuleNotFoundError:
        return None
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise AssertionError(f"{path} must parse as a YAML mapping")
    return data


def _walk(value: object) -> list[str]:
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        found: list[str] = []
        for item in value:
            found.extend(_walk(item))
        return found
    if isinstance(value, dict):
        found = []
        for item in value.values():
            found.extend(_walk(item))
        return found
    return []


def _upload_artifact_values(data: dict) -> list[str]:
    values: list[str] = []
    for job in (data.get("jobs") or {}).values():
        if not isinstance(job, dict):
            continue
        for step in job.get("steps") or []:
            if not isinstance(step, dict):
                continue
            uses = str(step.get("uses") or "")
            if not uses.startswith("actions/upload-artifact@"):
                continue
            values.extend(_walk((step.get("with") or {}).get("path")))
    return values


def _upload_artifact_text_blocks(path: Path) -> list[str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    blocks: list[str] = []
    for index, line in enumerate(lines):
        if "uses: actions/upload-artifact@" not in line:
            continue
        blocks.append("\n".join(lines[index : index + 16]))
    return blocks


def validate_yaml_files() -> None:
    for path in sorted(ROOT.rglob("*.yml")) + sorted(ROOT.rglob("*.yaml")):
        data = _load_yaml(path)
        if data is None:
            text = path.read_text(encoding="utf-8")
            if ":" not in text:
                raise AssertionError(f"{path} does not look like YAML")
            print(f"yaml text ok: {path.relative_to(ROOT)}")
        else:
            print(f"yaml ok: {path.relative_to(ROOT)}")


def validate_no_private_artifact_uploads() -> None:
    for path in sorted(ROOT.rglob("*.yml")) + sorted(ROOT.rglob("*.yaml")):
        data = _load_yaml(path)
        text_values = _upload_artifact_values(data) if data is not None else _upload_artifact_text_blocks(path)
        for value in text_values:
            for pattern in PRIVATE_PATTERNS:
                if pattern in value:
                    raise AssertionError(
                        f"{path.relative_to(ROOT)} references private artifact pattern {pattern!r}"
                    )
    print("private artifact upload check ok")


def validate_reusable_workflow_contract() -> None:
    path = ROOT / ".github" / "workflows" / "auto-remediate.yml"
    workflow = _load_yaml(path)
    text = path.read_text(encoding="utf-8")
    if workflow is None:
        if "workflow_call:" not in text:
            raise AssertionError("auto-remediate.yml must expose workflow_call")
        if "contents: write" not in text or "pull-requests: write" not in text:
            raise AssertionError("auto-remediate.yml must grant contents and pull-requests write")
        print("reusable workflow contract ok")
        return
    on_block = workflow.get("on", workflow.get(True))
    if not isinstance(on_block, dict) or "workflow_call" not in on_block:
        raise AssertionError("auto-remediate.yml must expose workflow_call")
    permissions = workflow.get("permissions", {})
    for key in ("contents", "pull-requests"):
        if permissions.get(key) != "write":
            raise AssertionError(f"missing required permission: {key}: write")
    print("reusable workflow contract ok")


def validate_shared_helper_contract() -> None:
    workflow = (ROOT / ".github" / "workflows" / "auto-remediate.yml").read_text(encoding="utf-8")
    action_text = "\n".join(
        path.read_text(encoding="utf-8")
        for path in sorted((ROOT / "actions").rglob("*.yml"))
    )
    helper_text = "\n".join(
        path.read_text(encoding="utf-8")
        for path in (
            ROOT / "scripts" / "remediation-core.sh",
            ROOT / "scripts" / "run-agent.sh",
            ROOT / "scripts" / "stage-paths.py",
        )
    )
    remediation_action = (ROOT / "actions" / "remediation-core" / "action.yml").read_text(encoding="utf-8")
    if "reach-testbed" in workflow or "reach-testbed" in action_text:
        raise AssertionError("workflow/actions must not wrap testbed-specific scripts")
    combined_text = "\n".join((workflow, action_text, helper_text, remediation_action))
    for forbidden in (
        "REACHABLE_RUN_PROJECT_TESTS",
        "REACHABLE_TEST_PRESET",
        "REACHABLE_PROJECT_TEST_COMMAND",
        "run_project_tests",
        "test_preset",
        "project_test_command",
        "bash -lc",
    ):
        if forbidden in combined_text:
            raise AssertionError(f"project-test execution surface must not be exposed: {forbidden}")
    if "python -m reachable.ci.proof_page" not in workflow:
        raise AssertionError("workflow must render the standardized reachable.ci proof/status page")
    for expected in (
        "normalized_mode=\"$(normalize_choice ai_mode \"${REACHABLE_AI_MODE}\" openai-codex openai-gpt anthropic-claude)\"",
        "ai_mode=openai-gpt is scan-only",
        "REACHABLE_PROOF_FAIL_ON",
        "if [ -z \"${REACHABLE_AGENT_MODEL:-}\" ]; then",
        "REACHABLE_AGENT_TIMEOUT_SEC",
        "uses: sthenos-security/reach-ci-github/actions/remediation-core@v1",
        "Reachable Python package is unavailable; skipping report publication.",
        "--pull-request-url",
        ".reachable/ci-artifacts/release-proof",
        "uses: actions/configure-pages@v6",
        "uses: actions/upload-pages-artifact@v5",
        "uses: actions/deploy-pages@v5",
        "hashFiles('.reachable/ci-artifacts/release-proof/index.html') != ''",
        ".reachable/ci-artifacts/reachable-after-final.sarif",
        ".reachable/ci-artifacts/reachable-report.json",
        ".reachable/ci-artifacts/reachable-summary.txt",
        "::warning title=Reachable JSON export unavailable::",
        "::warning title=Reachable summary export unavailable::",
    ):
        if expected not in workflow:
            raise AssertionError(f"workflow is missing standardized report output: {expected}")
    for expected in (
        "chmod +x \"$toolkit_root/scripts/run-agent.sh\" \"$toolkit_root/scripts/remediation-core.sh\"",
        "export REACHABLE_AGENT_RUNNER=\"$toolkit_root/scripts/run-agent.sh\"",
        "export REACHABLE_STAGE_PATHS_PY=\"$toolkit_root/scripts/stage-paths.py\"",
        "export REACHABLE_CORE_OUTPUTS_PATH=\"$outputs_file\"",
        "\"$toolkit_root/scripts/remediation-core.sh\"",
        "cat \"$outputs_file\" >> \"$GITHUB_ENV\"",
        "reachctl remediate .",
        "--context ci",
        "--output-dir .reachable/remediation-bundle",
        "--mode branch",
        "run_with_timeout \"$agent_timeout_sec\"",
        "timeout --kill-after=30s \"${timeout_sec}s\"",
        "subprocess.run(cmd, check=False, timeout=timeout_s).returncode",
        "reachctl remediate . --output-dir .reachable/remediation-bundle --cleanup",
        "git ls-files --modified --others --exclude-standard -z",
        "git add --pathspec-from-file=\"$stage_list\" --pathspec-file-nul",
        "codex exec",
        "--dangerously-bypass-approvals-and-sandbox",
        "--skip-git-repo-check",
        "--permission-mode bypassPermissions",
        "--no-session-persistence",
        "--verbose",
        "--output-format stream-json",
        "Apply the Reachable remediation task provided on stdin",
        "name.startswith(\"reachable-\")",
    ):
        if expected not in helper_text and expected not in remediation_action:
            raise AssertionError(f"helper contract missing: {expected}")
    if workflow.find("Push remediation branch") > workflow.find("Publish report"):
        raise AssertionError("remediation branch must be committed before proof page publication")
    if workflow.find("Open remediation PR") > workflow.find("Publish report"):
        raise AssertionError("PR URL must be available before proof page publication")
    pr_action = (ROOT / "actions" / "open-remediation-pr" / "action.yml").read_text(encoding="utf-8")
    for expected in (
        "pr-created=false",
        "GitHub rejected automatic PR creation",
        "open a PR manually",
    ):
        if expected not in pr_action:
            raise AssertionError(f"PR action must expose manual fallback behavior: {expected}")
    setup_action = (ROOT / "actions" / "setup-reachable" / "action.yml").read_text(encoding="utf-8")
    for expected in (
        "for attempt in 1 2 3",
        "Reachable installer failed after",
        "Reachable installer attempt",
    ):
        if expected not in setup_action:
            raise AssertionError(f"setup action must retry installer failures: {expected}")
    print("shared helper/status page contract ok")


def main() -> None:
    validate_yaml_files()
    validate_no_private_artifact_uploads()
    validate_reusable_workflow_contract()
    validate_shared_helper_contract()


if __name__ == "__main__":
    main()
