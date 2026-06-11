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

## Customer Integration Path

If you are integrating autonomous remediation into a GitHub repository, the
customer path is:

1. Choose the operating lane.
   Start with `remediate=true` and `create_pr=true` for a full autonomous
   remediation PR, or use `remediate=false` for assessment-only evidence while
   you validate rollout controls.
2. Enable the GitHub repository settings in
   [Repository Settings](#repository-settings).
   The important bits are write permissions for `GITHUB_TOKEN`, PR creation by
   Actions, and permission to call this reusable workflow.
3. Add one model-provider secret.
   Use `OPENAI_API_KEY` for `codex-openai` (alias `openai-codex`) or
   `ANTHROPIC_API_KEY` for `claude-anthropic` (alias `anthropic-claude`).
   Optional Reachable enrichment secrets are listed in
   [Secrets And Variables](#secrets-and-variables).
4. Add the small caller workflow from [Minimal Workflow](#minimal-workflow), or
   generate it from the SDK in [SDK Usage](#sdk-usage).
5. Pick the test behavior.
   If the repository has a normal stack, set `run_project_tests=true` and choose
   an allowlisted `test_preset` such as `go`, `python-pytest`, or `npm`. For
   monorepos or unusual test topology, leave Reachable project tests disabled
   and rely on the repository's existing CI/branch protection.
6. Run it manually first.
   Use `workflow_dispatch` on the default branch. After the proof artifacts and
   remediation PR look right, add a schedule or call this reusable workflow from
   your release pipeline.

On each autonomous remediation run, the workflow:

1. Installs the pinned or latest Reachable wheel.
2. Scans the target branch and stores the source of truth in `repo.db`.
3. Creates a bounded remediation branch.
4. Builds a DB-backed remediation bundle for the selected signal families.
5. Runs the selected coding-agent lane against that branch.
   The Claude lane runs Claude Code non-interactively and feeds the generated
   remediation task on stdin.
6. Runs the selected project test preset when enabled.
7. Rescans the branch to produce proof from the database, not from stale JSON.
8. Pushes the branch, opens a PR when configured, and uploads sanitized proof
   artifacts.

The review object for the customer is the remediation PR plus the Reachable
proof artifacts. Review the code diff, project-test result, release-blocker
count, and proof page before merging. The reusable workflow intentionally hides
private prompts, raw databases, raw witnesses, and agent transcripts.

Recommended production defaults:

| Setting | Recommended Value | Why |
|---------|-------------------|-----|
| `remediation_mode` | `codex-openai` | Default autonomous coding-agent lane. Accepted aliases are `openai-codex` and `anthropic-claude`. The Codex path pins `gpt-5.4-mini`; the Claude path pins `claude-sonnet-4-5-20250929`. |
| `agent_model` | empty | Optional remediation-model override passed to Codex or Claude when you intentionally want to test something else. |
| `max_batches` | `3` | Gives the agent multiple bounded passes without an open-ended loop. |
| `rescan_strategy` | `each_batch` | Proves each batch against fresh DB evidence. |
| `create_pr` | `true` | Keeps merge approval in normal GitHub review controls. |
| `publish_report` | `true` | Gives reviewers a stable proof artifact when Reachable setup succeeded; otherwise the workflow skips report rendering instead of failing late. |
| `fresh_scan` | `false` | Faster normal CI; use `true` for release smoke tests. |
| `run_project_tests` | repository-specific | Enable an allowlisted preset when it matches the repo; otherwise rely on existing CI. |

The `reach-testbed-go` demo follows the same customer path, but pins the beta
wheel, uses `fresh_scan=true`, and uses `max_batches=1` so the release smoke can
prove install, scan, remediation handoff, branch push, proof scan, and PR wiring
quickly. A production repository should increase batches only when it wants the
workflow to address a larger queue in one run.

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

The same caller is available as a checked-in example at
[`examples/basic/.github/workflows/reachable-remediation.yml`](examples/basic/.github/workflows/reachable-remediation.yml).

Then configure one model-provider secret:

| Mode | Required Secret | Agent Lane |
|------|-----------------|------------|
| `codex-openai` or `openai-codex` | `OPENAI_API_KEY` | Codex with OpenAI |
| `claude-anthropic` or `anthropic-claude` | `ANTHROPIC_API_KEY` | Claude Code with Anthropic |

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

There are four configuration surfaces. Keep them separate:

| Surface | Where it lives | Who sets it | Purpose |
|---------|----------------|-------------|---------|
| SDK config | `reachable.ci.autoremediation.GitHubAutoRemediationConfig` | Customer app or installer script | Generates the small caller workflow. |
| Workflow inputs | `with:` on `auto-remediate.yml@v1` | Caller workflow or manual dispatch wrapper | Controls each CI run. |
| GitHub secrets/variables | Repository or organization Actions settings | Repository owner | Supplies credentials, release pinning, and optional install source. |
| Runtime environment | Inside `auto-remediate.yml` | Reusable workflow | Normalizes inputs for shell steps; customers should not set these directly. |

### SDK Config

These fields are accepted by `GitHubAutoRemediationConfig` when generating a
caller workflow.

| Field | Default | Generated input or behavior | Notes |
|-------|---------|-----------------------------|-------|
| `workflow_name` | `Reachable Auto Remediation` | Workflow `name` | Display name in GitHub Actions. |
| `reusable_workflow` | `sthenos-security/reach-ci-github/.github/workflows/auto-remediate.yml@v1` | Job `uses` | Must include an explicit ref such as `@v1`. |
| `target_branch` | `main` | `target_branch` dispatch default | Branch to scan or verify. |
| `remediation_mode` | `codex-openai` | `remediation_mode` | `codex-openai` (alias `openai-codex`) requires `OPENAI_API_KEY` and defaults to `gpt-5.4-mini`; `claude-anthropic` (alias `anthropic-claude`) requires `ANTHROPIC_API_KEY` and defaults to `claude-sonnet-4-5-20250929`. |
| `agent_model` | empty | `agent_model` | Optional remediation-model override passed through to the selected coding agent. Leave unset for the pinned defaults. |
| `prompt_profile` | `balanced` | `prompt_profile` | `safe`, `balanced`, `aggressive`, `release`, or `nightly`. |
| `signal_types` | `all` | `signal_types` | Comma-separated families or `all`. |
| `max_batches` | `3` | `max_batches` | Must be 1-10. The loop stops early if DB proof is clean. |
| `rescan_strategy` | `each_batch` | `rescan_strategy` | `each_batch` or `final`. |
| `create_pr` | `true` | `create_pr` | Opens a PR only after a branch is pushed. |
| `publish_report` | `true` | `publish_report` | Publishes sanitized proof artifacts. If Reachable never finished setup, the workflow skips report rendering instead of failing during cleanup. |
| `require_ai` | `true` | `require_ai` | Fails early when the selected provider key is missing. |
| `fresh_scan` | `false` | `fresh_scan` | Deletes `~/.reachable` before install/scan when true. |
| `run_project_tests` | `false` | `run_project_tests` | Runs only allowlisted presets. |
| `test_preset` | `none` | `test_preset` | See [Common Test Presets](#common-test-presets). |
| `project_test_command` | empty | none | Custom shell commands are rejected; use an allowlisted preset or downstream CI. |
| `schedule_cron` | empty | `on.schedule` | Optional cron trigger in the generated caller workflow. |

### Required Provider Secret

| Secret | Required When | Purpose |
|--------|---------------|---------|
| `OPENAI_API_KEY` | `remediation_mode=codex-openai` or `openai-codex` | Used by Reachable AI analysis and the Codex coding-agent lane. |
| `ANTHROPIC_API_KEY` | `remediation_mode=claude-anthropic` or `anthropic-claude` | Used by Reachable AI analysis and the Claude Code lane. |

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

### Optional GitHub Variables

Most repositories do not need variables when using an SDK-generated workflow.
Set these only when you want an organization-wide default without editing the
caller workflow.

| Variable | Default | Purpose |
|----------|---------|---------|
| `REACHABLE_DIST_REPO` | `sthenos-security/reach-dist` | Distribution repository containing `install.sh`. |
| `REACHABLE_VERSION` | empty/latest | Optional release pin when the caller does not pass `reachable_version`. |

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
| `scan_extra_flags` | empty | Optional additional flags passed to `reachctl scan`; keep empty unless Reachable support asks for a specific scan flag. |
| `create_pr` | `true` | Open a PR after DB proof passes. |
| `publish_report` | `true` | Publish sanitized proof artifacts and status page. |
| `require_ai` | `true` | Fail early if the selected provider key is missing. |
| `fresh_scan` | `false` | Delete the local Reachable cache before the scan. |
| `run_project_tests` | `false` | Run an allowlisted test preset after agent edits. Disabled by default because Reachable cannot know a customer's test layout. |
| `test_preset` | `none` | Optional preset: `go`, `python-pytest`, `python-unittest`, `maven`, `gradle`, `npm`, `pnpm`, `yarn`, `rust`, `dotnet`, `ruby-rspec`, `phpunit`, `swift`, or `elixir`. |
| `reachable_version` | empty | Pin a Reachable release version. Empty uses the installer default/latest. |
| `reachable_dist_repo` | `sthenos-security/reach-dist` | Distribution repository containing `install.sh`. |

### Runtime Environment

The reusable workflow maps inputs and secrets into environment variables for
its shell steps. These are implementation details; set workflow inputs instead
of setting these directly.

| Environment variable | Derived from | Used for |
|----------------------|--------------|----------|
| `REACHABLE_DIST_REPO` | `reachable_dist_repo` | Installer source repository. |
| `REACHABLE_VERSION` | `reachable_version` | Installer release pin. |
| `REACHABLE_REMEDIATE_ENABLED` | `remediate` | Enables code-writing remediation. |
| `REACHABLE_RESCAN_ONLY` | `rescan_only` | Verifies an existing branch without editing. |
| `REACHABLE_REMEDIATION_MODE` | `remediation_mode` | Selects Codex/OpenAI or Claude/Anthropic lane. |
| `REACHABLE_PROMPT_PROFILE` | `prompt_profile` | Passed to `reachctl remediate`. |
| `REACHABLE_SIGNAL_TYPES` | `signal_types` | Selects signal families for the bundle. |
| `REACHABLE_MAX_BATCHES` | `max_batches` | Bounds remediation loop count. |
| `REACHABLE_RESCAN_STRATEGY` | `rescan_strategy` | Controls proof scan cadence. |
| `REACHABLE_SCAN_EXTRA_FLAGS` | `scan_extra_flags` | Additional scan flags, normally empty. |
| `REACHABLE_CREATE_PR` | `create_pr` | Controls PR creation. |
| `REACHABLE_PUBLISH_REPORT` | `publish_report` | Controls proof artifact publication. |
| `REACHABLE_REQUIRE_AI` | `require_ai` | Credential preflight behavior. |
| `REACHABLE_FRESH_SCAN` | `fresh_scan` | Cache deletion behavior. |
| `REACHABLE_RUN_PROJECT_TESTS` | `run_project_tests` | Enables test preset execution. |
| `REACHABLE_TEST_PRESET` | `test_preset` | Chooses the project test command. |
| `REACHABLE_AGENT` | resolved from `remediation_mode` | `codex` or `claude`. |
| `REACHABLE_LLM_PROVIDER` | resolved from `remediation_mode` | `openai` or `claude` for Reachable scan AI. |
| `REACHABLE_REMEDIATION_BRANCH` | generated by workflow | Branch name for agent edits and proof scan. |
| `REACHABLE_BRANCH_PUSHED` | generated by workflow | Guards PR creation. |
| `REACHABLE_PROOF_COMMIT` | generated by workflow | Commit shown in the proof page. |
| `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24` | fixed | Keeps GitHub JavaScript actions on Node 24. |
| `NODE_OPTIONS` | fixed | Suppresses Node runtime deprecation noise. |

### Demo Wrapper Values

The `reach-testbed-go` demo uses the same public SDK/reusable workflow path,
but pins a few values so the release demo is reproducible.

| Demo setting | Value | Why |
|--------------|-------|-----|
| Caller workflow | `reach-testbed-go/.github/workflows/reachable-remediate.yml` | Small wrapper generated from the SDK shape. |
| Reusable workflow | `sthenos-security/reach-ci-github/.github/workflows/auto-remediate.yml@v1` | Public customer-facing integration package. |
| `reachable_version` | current beta, for example `1.0.0b104` | Ensures the demo tests the beta wheel under release validation. |
| `reachable_dist_repo` | `sthenos-security/reach-dist` | Pulls the public release installer and wheels. |
| `remediation_mode` | `codex-openai` | Exercises the default Codex lane. |
| `prompt_profile` | `balanced` | Keeps fixes bounded for a demo-sized queue. |
| `signal_types` | `all` | Exercises CVE, CWE, secret, DLP, and AI findings. |
| `max_batches` | `1` for beta smoke, higher for full demos | Fast proof of the CI path; increase only when proving multi-batch remediation. |
| `rescan_strategy` | `each_batch` | Proves the branch after every batch. |
| `fresh_scan` | `true` for beta smoke | Avoids cache hiding release/install regressions. |
| `run_project_tests` | `true` | Runs the Go preset after agent edits. |
| `test_preset` | `go` | Runs `go test ./...`. |

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
| Release proof page | Standard `reachable.ci.proof_page` output: branch, commit, scan ID, release blockers, defended items, PR/run links, and expandable threat-vector plus stack-style code/data-flow evidence. |
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
