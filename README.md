# Reachable CI for GitHub

Reusable GitHub Actions integration for Reachable autonomous remediation.

This repository is the customer-facing CI package. Application repositories
should call the reusable workflow here instead of copying demo scripts from a
testbed repository.

## What It Does

| Lane | Purpose | Code Changes | Pull Request |
|------|---------|--------------|--------------|
| Assess | Scan the target branch and publish DB-backed posture evidence. | No | No |
| Patch branch | Create bounded remediation changes and verify the branch. | Yes | Optional |
| Patch + PR | Create bounded remediation changes, verify, publish proof, and open a review PR. | Yes | Yes |
| Rescan only | Verify an existing remediation branch without editing it. | No | No |

The pass/fail verdict is based on Reachable `repo.db` evidence. SARIF and other
exports are compatibility artifacts, not the source of truth.

## Minimal Setup

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

## Inputs

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

Reachable does not accept arbitrary test commands in this reusable workflow.
Customers with custom test topology should keep those commands in their own CI
jobs and let branch protection decide whether the remediation PR can merge.

## Published Evidence

The workflow publishes sanitized evidence only:

| Artifact | Purpose |
|----------|---------|
| Release proof page | Standard `reachable.ci.proof_page` output: branch, commit, scan ID, release blockers, defended items, and PR/run links. |
| Summary JSON | Machine-readable run summary. |
| Remediation ledger | Sanitized list of remediation rules and outcomes. |
| SARIF export | Compatibility upload for GitHub code scanning. Not authoritative. |

The workflow must not publish private remediation prompts, generated rules,
agent transcripts, raw witnesses, or local databases.

## SDK Boundary

The reusable workflow is intentionally thin. Standard behavior belongs in the
Reachable wheel under `reachable.ci`, including:

- workflow generation
- settings and secret doctor output
- cache/install evidence
- DB-backed proof gates
- release proof pages
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
