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
    if workflow is None:
        text = path.read_text(encoding="utf-8")
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


def main() -> None:
    validate_yaml_files()
    validate_no_private_artifact_uploads()
    validate_reusable_workflow_contract()


if __name__ == "__main__":
    main()
