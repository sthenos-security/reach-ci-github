# Reachable CI for GitHub

Reusable GitHub Actions integration for Reachable autonomous remediation.

This repository is the customer-facing GitHub CI package. Application
repositories should call the reusable workflow here, or generate that caller
workflow with the Reachable SDK, instead of copying demo scripts from a testbed
repository.

The goal is simple: set a small number of variables/secrets, run a workflow, and
receive DB-backed release evidence plus an optional remediation branch and PR.

## Quick Start

1. Add one model provider secret to the application repository:
   `OPENAI_API_KEY` for the default Codex/OpenAI lane, or `ANTHROPIC_API_KEY`
   for the Claude/Anthropic lane.
2. Enable the GitHub repository settings listed in
   [Repository Settings](#repository-settings).
3. Add `.github/workflows/reachable-remediation.yml` using the example below,
   or generate it with the SDK snippet in [SDK Usage](#sdk-usage).
4. Run **Actions -> Reachable Auto Remediation -> Run workflow**.
5. Review the proof artifacts, remediation branch, and PR if `create_pr=true`.

## What It Does

| Lane | Purpose | Code Changes | Pull Request |
|------|---------|--------------|--------------|
| Assess | Scan the target branch and publish DB-backed posture evidence. | No | No |
| Patch branch | Create bounded remediation changes and verify the branch. | Yes | Optional |
| Patch + PR | Create bounded remediation changes, verify, publish proof, and open a review PR. | Yes | Yes |
| Rescan only | Verify an existing remediation branch without editing it. | No | No |

The pass/fail verdict is based on Reachable `repo.db` evidence. SARIF and other
exports are compatibility artifacts, not the source of truth.

## SDK Usage

When the Reachable wheel is installed, generate the caller workflow from Python:

```python
from reachable.ci.autoremediation import (
    GitHubAutoRemediationConfig,
    write_github_workflow,
)

write_github_workflow(
    ".github/workflows/reachable-remediation.yml",
    GitHubAutoRemediationConfig(
        remediation_mode="codex-openai",
        max_batches=3,
        create_pr=True,
        publish_report=True,
        run_project_tests=False,
        test_preset="none",
    ),
)
```

For a simple Go repository:

```python
write_github_workflow(
    ".github/workflows/reachable-remediation.yml",
    GitHubAutoRemediationConfig(
        remediation_mode="codex-openai",
        max_batches=3,
        create_pr=True,
        run_project_tests=True,
        test_preset="go",
    ),
)
```

The SDK deliberately does not accept arbitrary shell test commands. Use one of
the allowlisted presets or keep custom test orchestration in your own CI jobs.

## Minimal Workflow

Add this file to the application repository:

```yaml
# .github/workflows/reachable-remediation.yml
name: Reachable Auto Remediation

on:
  workflow_dispatch:

permissions:
  contents: write
  pull-requests: write
  security-events: write
  actions: write
  pages: write
  id-token: write

jobs:
  reachable:
    uses: sthenos-security/reach-ci-github/.github/workflows/auto-remediate.yml@v1
    with:
      target_branch: main
      remediate: true
      rescan_only: false
      remediation_mode: codex-openai
      max_batches: 3
      rescan_strategy: each_batch
      create_pr: true
      run_project_tests: false
      test_preset: none
    secrets: inherit
```

Then configure one model-provider secret:

| Mode | Required Secret | Agent Lane |
|------|-----------------|------------|
| `codex-openai` | `OPENAI_API_KEY` | Codex with OpenAI |
| `claude-anthropic` | `ANTHROPIC_API_KEY` | Claude Code with Anthropic |

## Repository Settings

| Setting | Recommended Value | Why |
|---------|-------------------|-----|
| Actions and reusable workflows | Allow `sthenos-security/reach-ci-github` or allow all actions and reusable workflows | Lets the caller invoke this reusable workflow. |
| Workflow permissions | Read and write permissions | Lets `GITHUB_TOKEN` push branches, upload reports, and publish pages. |
| Allow GitHub Actions to create and approve pull requests | Enabled | Lets `GITHUB_TOKEN` open the remediation PR. |
| Pull request creation | Collaborators only, or an organization-approved equivalent | Keeps public repos from accepting arbitrary outside PR noise. |
| Fork workflow approval | Require approval for all external contributors | Avoids running untrusted fork workflows automatically. |

The normal path uses the built-in `GITHUB_TOKEN`. A personal access token is not
required for branch creation or PR creation when the repository settings above
are enabled.

## Secrets And Variables

### Required Provider Secret

| Secret | Required When | Purpose |
|--------|---------------|---------|
| `OPENAI_API_KEY` | `remediation_mode=codex-openai` | Used by Reachable AI analysis and the Codex coding-agent lane. |
| `ANTHROPIC_API_KEY` | `remediation_mode=claude-anthropic` | Used by Reachable AI analysis and the Claude Code lane. |

Set these in GitHub:

```text
Repository -> Settings -> Secrets and variables -> Actions -> New repository secret
```

### Optional Reachable Secrets

| Secret | Purpose |
|--------|---------|
| `REACHABLE_API_KEY` | Optional Reachable product/cloud entitlement or enrichment token. |
| `REACHABLE_GITHUB_TOKEN` | Optional scanner enrichment token for GitHub metadata/package context. Not used to control CI. |
| `MCP_GITHUB_TOKEN` | Optional MCP context token. Not used to control CI. |

### Workflow Inputs

These are selected when a user starts the workflow manually or when a wrapper
workflow calls this reusable workflow.

| Input | Default | Purpose |
|-------|---------|---------|
| `target_branch` | `main` | Branch to scan, or branch to verify when `rescan_only=true`. |
| `remediate` | `true` | Kill switch for code-writing remediation. |
| `rescan_only` | `false` | Verify an existing branch without editing code. |
| `remediation_mode` | `codex-openai` | Selects the coding-agent/provider lane. |
| `prompt_profile` | `balanced` | Bundling profile passed to Reachable. |
| `signal_types` | `all` | Signal families to include in the remediation bundle. |
| `max_batches` | `3` | Maximum serialized remediation loops. The workflow stops early when no release blockers remain. |
| `rescan_strategy` | `each_batch` | Rescan after each batch or only at the end. |
| `create_pr` | `true` | Open a PR after DB proof passes. |
| `publish_report` | `true` | Publish sanitized proof artifacts and status page. |
| `require_ai` | `true` | Fail early if the selected provider key is missing. |
| `fresh_scan` | `false` | Delete the local Reachable cache before the scan. |
| `run_project_tests` | `false` | Run an allowlisted test preset after agent edits. Disabled by default because Reachable cannot know a customer's test layout. |
| `test_preset` | `none` | Optional preset: `go`, `python-pytest`, `python-unittest`, `maven`, `gradle`, `npm`, `pnpm`, `yarn`, `rust`, `dotnet`, `ruby-rspec`, `phpunit`, `swift`, or `elixir`. |
| `reachable_version` | empty | Pin a Reachable release version. Empty uses the installer default/latest. |
| `reachable_dist_repo` | `sthenos-security/reach-dist` | Distribution repository containing `install.sh`. |

### Common Test Presets

| Preset | Command |
|--------|---------|
| `go` | `go test ./...` |
| `python-pytest` | `python -m pytest` |
| `python-unittest` | `python -m unittest` |
| `maven` | `mvn test` |
| `gradle` | `gradle test` |
| `npm` | `npm test` |
| `pnpm` | `pnpm test` |
| `yarn` | `yarn test` |
| `rust` | `cargo test` |
| `dotnet` | `dotnet test` |
| `ruby-rspec` | `bundle exec rspec` |
| `phpunit` | `vendor/bin/phpunit` |
| `swift` | `xcodebuild test` |
| `elixir` | `mix test` |

Reachable cannot know where a customer's tests live in a monorepo. For complex
repositories, leave `run_project_tests=false` and rely on existing branch
protection or downstream CI jobs to validate the remediation branch.

Reachable does not accept arbitrary test commands in this reusable workflow.
Customers with custom test topology should keep those commands in their own CI
jobs and let branch protection decide whether the remediation PR can merge.

## Published Evidence

The workflow publishes sanitized evidence only:

| Artifact | Purpose |
|----------|---------|
| Release proof page | Standard `reachable.ci.proof_page` output: branch, commit, scan ID, release blockers, defended items, PR/run links, and expandable threat-vector/data-flow evidence. |
| Summary JSON | Machine-readable run summary. |
| Remediation ledger | Sanitized list of remediation rules and outcomes. |
| SARIF export | Compatibility upload for GitHub code scanning. Not authoritative. |

The workflow must not publish private remediation prompts, generated rules,
agent transcripts, raw witnesses, or local databases.

## Runbook

### Assess Only

Use this when you want a DB-backed posture report without code changes.

```yaml
with:
  remediate: false
  rescan_only: false
  publish_report: true
```

Expected result:

- baseline scan runs
- sanitized proof artifacts are uploaded
- no branch is created
- no PR is opened

### Remediate Without PR

Use this when you want to inspect the generated branch before automating PRs.

```yaml
with:
  remediate: true
  create_pr: false
  max_batches: 3
  rescan_strategy: each_batch
```

Expected result:

- remediation branch is pushed
- proof scan runs against that branch
- proof page records branch, commit, scan ID, and release blockers
- reviewer opens a PR manually if desired

### Remediate And Open PR

Use this after the repository settings are validated.

```yaml
with:
  remediate: true
  create_pr: true
  max_batches: 3
  rescan_strategy: each_batch
```

Expected result:

- remediation branch is pushed
- proof scan runs against that branch
- PR is opened with the DB-backed proof available as artifacts/report

### Verify Existing Branch

Use this to prove a remediation branch again without changing code.

```yaml
with:
  target_branch: reachable-remediate-YYYYMMDD-HHMMSS-COMMIT
  remediate: false
  rescan_only: true
```

Expected result:

- selected branch is scanned
- proof page shows current blockers or pass state
- no code is edited

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| `remediation_mode=codex-openai requires OPENAI_API_KEY` | Missing provider secret. | Add `OPENAI_API_KEY` to repository or organization Actions secrets. |
| PR branch pushed but no PR opened | GitHub Actions cannot create PRs. | Enable "Allow GitHub Actions to create and approve pull requests" and `pull-requests: write`. |
| Proof page reports blockers after remediation | The agent fixed only part of the queue or a finding needs manual review. | Review the branch and proof summary; rerun with more batches only if the remaining item is safe to automate. |
| Project tests did not run | `run_project_tests=false` or `test_preset=none`. | Select an allowlisted preset, or rely on the repository's existing CI. |
| Custom test command needed | Monorepo/project-specific test layout. | Keep that command in the application's own CI, not inside this reusable security workflow. |

## SDK Boundary

The reusable workflow is intentionally thin. Standard behavior belongs in the
Reachable wheel under `reachable.ci`, including:

- workflow generation
- settings and secret doctor output
- cache/install evidence
- DB-backed proof gates
- release proof pages
- expandable DB-backed evidence paths / simple call graph rows
- export sanitization
- PR/MR helper contracts

Demo repositories can keep extra expected-contract checks, but customer
repositories should only need variables and secrets.

## Manual PR Fallback

If an enterprise repository intentionally blocks Actions from opening PRs, the
workflow still pushes the remediation branch and publishes the branch name in
the proof page. A reviewer can open the PR manually:

```bash
gh pr create \
  --repo OWNER/REPO \
  --base main \
  --head reachable-remediate-YYYYMMDD-HHMMSS-COMMIT \
  --title "Reachable remediation proof" \
  --body "DB-backed remediation branch generated by Reachable CI."
```

## Status

This repository is the GitHub lane. GitLab support belongs in
`reach-ci-gitlab` and should be implemented with native GitLab CI templates,
Merge Requests, GitLab Pages, and GitLab security report exports.

## Local Validation

Run the package smoke check before tagging a release:

```bash
python3 scripts/validate-workflows.py
```

The validator checks every workflow/action YAML file and verifies the reusable
workflow does not publish private remediation handoff artifacts. If PyYAML is
installed, it also performs full YAML parsing.
