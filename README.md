# Reachable CI for GitHub

Reusable GitHub Actions integration for REACHABLE risk exposure reduction and
reviewable auto-remediation.

This repository is the customer-facing GitHub CI toolkit. Application
repositories should call the reusable workflow here, or generate that caller
workflow with the Reachable SDK, instead of copying demo scripts from a testbed
repository.

This repository now also exposes the root Marketplace action entrypoint:

```yaml
uses: sthenos-security/reach-ci-github@v1
```

That root `action.yml` is the publishable GitHub Marketplace unit. The
reusable workflow at
[`/.github/workflows/auto-remediate.yml`](.github/workflows/auto-remediate.yml)
remains the richer orchestration surface for customers who prefer a reusable
workflow contract.

The goal is simple: set a small number of variables/secrets, run a workflow, and
receive structured proof artifacts plus an optional remediation branch and PR
for human review.

Canonical docs:
- Site: <https://sthenosec.com/>
- Primer: <https://sthenosec.com/docs/primer>
- Auto-remediation overview: <https://sthenosec.com/resources/auto-remediation>

## Quick Start

1. Add the repository secrets Reachable needs:
   `OPENAI_API_KEY` for the default Codex/OpenAI lane, or `ANTHROPIC_API_KEY`
   for the Claude/Anthropic lane. Add `MCP_GITHUB_TOKEN` when you want GitHub
   source reads, MCP GitHub cloning, and git clone fallback.
2. Enable the GitHub repository settings listed in
   [Repository Settings](#repository-settings).
3. Add `.github/workflows/reachable-remediation.yml` using the example below,
   or generate it with the SDK snippet in [SDK Usage](#sdk-usage).
4. Run **Actions -> Reachable Auto Remediation -> Run workflow**.
5. Review the proof artifacts, remediation branch, and PR if `create_pr=true`.

## Marketplace Action

If you want the GitHub Marketplace install surface, use the root action from
this repository. The caller workflow still needs normal GitHub job permissions
and a checkout step, but the product entrypoint is now the repo root instead of
an internal sub-action.

```yaml
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
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: sthenos-security/reach-ci-github@v1
        with:
          ai_mode: openai-codex
          fail_on: exploitable
          create_pr: "true"
          publish_report: "true"
          publish_pages: "true"
          openai_api_key: ${{ secrets.OPENAI_API_KEY }}
          mcp_github_token: ${{ secrets.MCP_GITHUB_TOKEN }}
```

The Marketplace action defaults `target_branch` to the current checkout branch.
Use `target_branch` explicitly when your workflow checks out a different ref
than the branch you want the remediation PR to target.

**Required tokens for customer-facing use**

- AI token: set `OPENAI_API_KEY` for the default Codex/OpenAI lane, or
  `ANTHROPIC_API_KEY` for the Claude/Anthropic lane. This is required.
- MCP GitHub token: set `MCP_GITHUB_TOKEN` as a fine-grained PAT with
  `Contents: Read-only` on the repos Reachable should inspect. This is
  recommended for faster richer clone, source, and package context, and is also
  used when MCP source fetch falls back to plain git clone.
- GitHub control token: GitHub Actions already provides `GITHUB_TOKEN`
  automatically for checkout, branch push, PR creation, artifact upload, and
  Pages publishing.

## What It Does

| Lane | Purpose | Code Changes | Pull Request |
|------|---------|--------------|--------------|
| Assess | Scan the target branch and publish structured proof artifacts. | No | No |
| Patch branch | Create bounded remediation changes and verify the branch. | Yes | Optional |
| Patch + PR | Create bounded remediation changes, verify, publish proof, and open a review PR. | Yes | Yes |
| Rescan only | Verify an existing remediation branch without editing it. | No | No |

The pass/fail verdict is based on REACHABLE's local evidence record. `repo.db`
is the internal structured store behind that record; SARIF and other exports
are compatibility artifacts, not the source of truth.

## Customer Integration Path

If you are integrating reviewable auto-remediation into a GitHub repository, the
customer path is:

1. Choose the operating lane.
   Start with `remediate=true` and `create_pr=true` for a full remediation PR,
   or use `remediate=false` for read-only evidence while you confirm rollout
   controls.
2. Enable the GitHub repository settings in
   [Repository Settings](#repository-settings).
   The important bits are write permissions for `GITHUB_TOKEN`, PR creation by
   Actions, and permission to call this reusable workflow.
3. Add one model-provider secret.
   Use `OPENAI_API_KEY` for `ai_mode=openai-gpt` or `ai_mode=openai-codex`,
   or `ANTHROPIC_API_KEY` for `ai_mode=anthropic-claude`.
   Optional Reachable enrichment secrets are listed in
   [Secrets And Variables](#secrets-and-variables).
4. Add the small caller workflow from [Minimal Workflow](#minimal-workflow), or
   generate it from the SDK in [SDK Usage](#sdk-usage).
5. Run it manually first.
   Use `workflow_dispatch` on the default branch. After the proof artifacts and
   remediation PR look right, add a schedule or call this reusable workflow from
   your release pipeline.

On each auto-remediation run, the workflow:

1. Installs the pinned or latest Reachable wheel.
2. Scans the target branch and records the evidence in REACHABLE's local
   evidence store.
3. Creates a bounded remediation branch.
4. Builds a remediation bundle for the selected signal families.
5. Runs the selected coding-agent lane against that branch.
   The Claude lane runs Claude Code non-interactively and feeds the generated
   remediation task on stdin.
6. Rescans the branch to produce proof from the current branch state.
7. Pushes the branch, opens a PR when configured, and uploads sanitized proof
   artifacts.

Use one customer-facing threshold: `fail_on`.

For remediation runs, the baseline scan is there to collect evidence and build
the remediation bundle. The reusable workflow keeps that baseline non-blocking,
then applies `fail_on` to the proof scan after remediation.

In practice:

- scan-only mode applies `fail_on` directly, for example `fail_on: exploitable`
- remediation mode still uses the same `fail_on` value, but applies it at the
  end of the proof scan after remediation

The review object for the customer is the remediation PR plus the Reachable
proof artifacts. Review the code diff, release-blocker count, proof page, and
the repository's normal CI result before merging. The reusable workflow
intentionally hides private prompts, raw databases, raw witnesses, and agent
transcripts.

Recommended production defaults:

| Setting | Recommended Value | Why |
|---------|-------------------|-----|
| `ai_mode` | `openai-codex` | Public lane selector. Use `openai-gpt` for OpenAI scan-only, `openai-codex` for OpenAI plus Codex remediation, or `anthropic-claude` for Anthropic plus Claude remediation. |
| `agent_model` | empty | Optional remediation-model override passed to Codex or Claude when you intentionally want to test something else. |
| `agent_timeout_sec` | `1800` | Per-batch coding-agent timeout. The timer resets for each remediation batch. |
| `max_batches` | `3` | Gives the agent multiple bounded passes without an open-ended loop. |
| `rescan_strategy` | `each_batch` | Proves each batch against fresh DB evidence. |
| `create_pr` | `true` | Keeps merge approval in normal GitHub review controls. |
| `publish_report` | `true` | Gives reviewers a stable proof artifact when Reachable setup succeeded; otherwise the workflow skips report rendering instead of failing late. |
| `fresh_scan` | `false` | Faster normal CI; use `true` for release smoke tests. |
The dedicated GitHub marketplace remediation demo follows the same customer
path, uses latest-by-default Reachable installation, `fresh_scan=true`, and
`max_batches=1` so the release smoke can
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
        ai_mode="openai-codex",
        max_batches=3,
        create_pr=True,
        publish_report=True,
    ),
)
```

The SDK deliberately does not accept project-test commands. The remediation
prompt asks the selected coding agent to run appropriate lint/build/test checks
when the repository exposes them, while the application repository's own CI and
branch protection remain the enforcement point. Reachable release harnesses may
run language-specific checks such as `go test ./...` against generated demo
branches as separate proof, outside this reusable workflow.

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
      fail_on: exploitable
      proof_fail_on: exploitable
      remediate: true
      rescan_only: false
      ai_mode: openai-codex
      max_batches: 3
      rescan_strategy: each_batch
      create_pr: true
    secrets: inherit
```

The same caller is available as a checked-in example at
[`examples/basic/.github/workflows/reachable-remediation.yml`](examples/basic/.github/workflows/reachable-remediation.yml).

Then configure one model-provider secret:

| Mode | Required Secret | Agent Lane |
|------|-----------------|------------|
| `openai-gpt` | `OPENAI_API_KEY` | OpenAI scan-only; rejected when `remediate=true` |
| `openai-codex` | `OPENAI_API_KEY` | OpenAI scan plus Codex remediation |
| `anthropic-claude` | `ANTHROPIC_API_KEY` | Anthropic scan plus Claude Code remediation |

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
| `ai_mode` | `openai-codex` | `ai_mode` | Public lane selector: `openai-gpt`, `openai-codex`, or `anthropic-claude`. |
| `agent_model` | empty | `agent_model` | Optional remediation-model override passed through to the selected coding agent. Leave unset for the pinned defaults. |
| `agent_timeout_sec` | `1800` | `agent_timeout_sec` | Positive integer timeout applied to each coding-agent batch. The timer resets on every batch. |
| `prompt_profile` | `balanced` | `prompt_profile` | `safe`, `balanced`, `aggressive`, `release`, or `nightly`. |
| `signal_types` | `all` | `signal_types` | Comma-separated families or `all`. |
| `max_batches` | `3` | `max_batches` | Must be 1-10. The loop stops early if DB proof is clean. |
| `rescan_strategy` | `each_batch` | `rescan_strategy` | `each_batch` or `final`. |
| `fail_on` | `exploitable` | `fail_on` | Single customer-facing policy threshold. The workflow keeps the baseline non-blocking during remediation, then applies this threshold to the proof scan. |
| `proof_fail_on` | empty | `proof_fail_on` | Optional post-remediation proof threshold override. Empty reuses `fail_on`. |
| `create_pr` | `true` | `create_pr` | Opens a PR only after a branch is pushed. |
| `publish_report` | `true` | `publish_report` | Publishes sanitized proof artifacts. If Reachable never finished setup, the workflow skips report rendering instead of failing during cleanup. |
| `require_ai` | `true` | `require_ai` | Fails early when the selected provider key is missing. |
| `fresh_scan` | `false` | `fresh_scan` | Deletes `~/.reachable` before install/scan when true. |
| `schedule_cron` | empty | `on.schedule` | Optional cron trigger in the generated caller workflow. |

### Required Provider Secret

| Secret | Required When | Purpose |
|--------|---------------|---------|
| `OPENAI_API_KEY` | `ai_mode=openai-gpt` or `ai_mode=openai-codex` | Used by Reachable AI analysis and, for `openai-codex`, the Codex coding-agent lane. |
| `ANTHROPIC_API_KEY` | `ai_mode=anthropic-claude` | Used by Reachable AI analysis and the Claude Code lane. |

Set these in GitHub:

```text
Repository -> Settings -> Secrets and variables -> Actions -> New repository secret
```

### CI Token Table

| Token | Create as | Minimum permission/scopes | Secret name | Why |
|-------|-----------|---------------------------|-------------|-----|
| AI token | OpenAI API key or Anthropic API key | Provider account key | `OPENAI_API_KEY` or `ANTHROPIC_API_KEY` | Required for representative Reachable analysis and the remediation lane |
| GitHub MCP token | GitHub fine-grained PAT | Repository access to the repos Reachable needs, `Contents: Read-only` | `MCP_GITHUB_TOKEN` | Recommended for GitHub source reads, MCP GitHub cloning, and package git clone fallback |
| GitHub control token | Built-in GitHub Actions token | Provided automatically by GitHub Actions | `GITHUB_TOKEN` | Checkout, branch push, report upload, Pages deploy, and PR creation |

For `MCP_GITHUB_TOKEN`, create a **fine-grained personal access token** at
<https://github.com/settings/personal-access-tokens/new>. Select the
**Resource owner** that owns the GitHub source repos Reachable may inspect. Use
**Only select repositories** for a small fixed set, or **All repositories** when
CI must read any current/future repo for that owner; **Public repositories** is
enough only for public source repos. Grant **Repository permissions -> Contents:
Read-only**; GitHub adds **Metadata: Read-only** automatically. Do not add write,
pull request, workflow, administration, or secret permissions.

There is no separate "MCP permission". The token's repository code/metadata read
access is what powers MCP GitHub cloning and the git clone fallback when MCP
cannot fetch a package directly. GitHub Actions' built-in `GITHUB_TOKEN` remains the CI
control token for checkout, branch push, report upload, Pages deploy, and PR
creation; `MCP_GITHUB_TOKEN` is not used to control CI. If you also need private
GitHub Packages, the primer covers when to use a classic PAT with
`read:packages`.

### Optional Reachable Secrets

| Secret | Purpose |
|--------|---------|
| `REACHABLE_API_KEY` | Optional Reachable product/cloud entitlement or enrichment token. |
| `REACHABLE_GITHUB_TOKEN` | Optional scanner enrichment token for GitHub metadata/package context. Not used to control CI. |
| `MCP_GITHUB_TOKEN` | Optional GitHub source token for MCP GitHub cloning and git clone fallback. Not used to control CI. |

### Optional GitHub Variables

Most repositories do not need variables when using an SDK-generated workflow.
Set these only when you want an organization-wide default without editing the
caller workflow.

| Variable | Default | Purpose |
|----------|---------|---------|
| `REACHABLE_DIST_REPO` | `sthenos-security/reach-dist` | Distribution repository containing `install.sh`. |

### Workflow Inputs

These are selected when a user starts the workflow manually or when a wrapper
workflow calls this reusable workflow.

| Input | Default | Purpose |
|-------|---------|---------|
| `target_branch` | `main` | Branch to scan, or branch to verify when `rescan_only=true`. |
| `remediate` | `true` | Kill switch for code-writing remediation. |
| `rescan_only` | `false` | Verify an existing branch without editing code. |
| `ai_mode` | `openai-codex` | Selects the scan/provider and remediation-agent lane. |
| `agent_timeout_sec` | `1800` | Per-batch timeout for the selected coding agent. The timeout resets on every remediation batch. |
| `prompt_profile` | `balanced` | Bundling profile passed to Reachable. |
| `signal_types` | `all` | Signal families to include in the remediation bundle. |
| `max_batches` | `3` | Maximum serialized remediation loops. The workflow stops early when no release blockers remain. |
| `rescan_strategy` | `each_batch` | Rescan after each batch or only at the end. |
| `proof_fail_on` | empty | Optional post-remediation proof threshold override. Empty reuses `fail_on`. |
| `scan_extra_flags` | empty | Optional additional flags passed to `reachctl scan`; keep empty unless Reachable support asks for a specific scan flag. |
| `create_pr` | `true` | Open a PR after DB proof passes. |
| `publish_report` | `true` | Publish sanitized proof artifacts and status page. |
| `require_ai` | `true` | Fail early if the selected provider key is missing. |
| `fresh_scan` | `false` | Delete the local Reachable cache before the scan. |
| `reachable_dist_repo` | `sthenos-security/reach-dist` | Distribution repository containing `install.sh`. |

### Runtime Environment

The reusable workflow maps inputs and secrets into environment variables for
its shell steps. These are implementation details; set workflow inputs instead
of setting these directly.

| Environment variable | Derived from | Used for |
|----------------------|--------------|----------|
| `REACHABLE_DIST_REPO` | `reachable_dist_repo` | Installer source repository. |
| `REACHABLE_REMEDIATE_ENABLED` | `remediate` | Enables code-writing remediation. |
| `REACHABLE_RESCAN_ONLY` | `rescan_only` | Verifies an existing branch without editing. |
| `REACHABLE_AI_MODE` | `ai_mode` | Selects `openai-gpt`, `openai-codex`, or `anthropic-claude`. |
| `REACHABLE_AGENT_TIMEOUT_SEC` | `agent_timeout_sec` | Positive integer timeout applied to each coding-agent batch. |
| `REACHABLE_PROMPT_PROFILE` | `prompt_profile` | Passed to `reachctl remediate`. |
| `REACHABLE_SIGNAL_TYPES` | `signal_types` | Selects signal families for the bundle. |
| `REACHABLE_MAX_BATCHES` | `max_batches` | Bounds remediation loop count. |
| `REACHABLE_RESCAN_STRATEGY` | `rescan_strategy` | Controls proof scan cadence. |
| `REACHABLE_FAIL_ON` | `fail_on` | Scan/baseline threshold. Baseline is forced non-blocking during remediation. |
| `REACHABLE_PROOF_FAIL_ON` | `proof_fail_on` or `fail_on` | Post-remediation proof threshold. |
| `REACHABLE_SCAN_EXTRA_FLAGS` | `scan_extra_flags` | Additional scan flags, normally empty. |
| `REACHABLE_CREATE_PR` | `create_pr` | Controls PR creation. |
| `REACHABLE_PUBLISH_REPORT` | `publish_report` | Controls proof artifact publication. |
| `REACHABLE_REQUIRE_AI` | `require_ai` | Credential preflight behavior. |
| `REACHABLE_FRESH_SCAN` | `fresh_scan` | Cache deletion behavior. |
| `REACHABLE_AGENT` | resolved from `ai_mode` | `codex` or `claude` for remediation-capable lanes. |
| `REACHABLE_LLM_PROVIDER` | resolved from `ai_mode` | `openai` or `claude` for Reachable scan AI. |
| `REACHABLE_REMEDIATION_BRANCH` | generated by workflow | Branch name for agent edits and proof scan. |
| `REACHABLE_BRANCH_PUSHED` | generated by workflow | Guards PR creation. |
| `REACHABLE_PROOF_COMMIT` | generated by workflow | Commit shown in the proof page. |
| `FORCE_JAVASCRIPT_ACTIONS_TO_NODE24` | fixed | Keeps GitHub JavaScript actions on Node 24. |
| `NODE_OPTIONS` | fixed | Suppresses Node runtime deprecation noise. |

### Demo Wrapper Values

The dedicated GitHub marketplace remediation demo uses the same public
SDK/reusable workflow path and keeps the demo-specific controls explicit.

| Demo setting | Value | Why |
|--------------|-------|-----|
| Caller workflow | `reach-testbed-github-marketplace/.github/workflows/reachable-remediate.yml` | Small wrapper generated from the SDK shape. |
| Reusable workflow | `sthenos-security/reach-ci-github/.github/workflows/auto-remediate.yml@v1` | Public customer-facing integration package. |
| `reachable_dist_repo` | `sthenos-security/reach-dist` | Pulls the public release installer and wheels. |
| `ai_mode` | `openai-codex` | Exercises the default Codex lane. |
| `prompt_profile` | `balanced` | Keeps fixes bounded for a demo-sized queue. |
| `signal_types` | `all` | Exercises CVE, CWE, secret, DLP, and AI findings. |
| `max_batches` | `1` for beta smoke, higher for full demos | Fast proof of the CI path; increase only when proving multi-batch remediation. |
| `rescan_strategy` | `each_batch` | Proves the branch after every batch. |
| `fresh_scan` | `true` for beta smoke | Avoids cache hiding release/install regressions. |
## Published Evidence

The workflow publishes sanitized evidence only:

| Name | Path | Produced by | Purpose |
|------|------|-------------|---------|
| Baseline SARIF | `.reachable/ci-artifacts/reachable.sarif` | `Baseline scan` | Machine-readable baseline findings for GitHub/security tooling consumers. |
| Release proof page | `.reachable/ci-artifacts/release-proof/index.html` | `Publish report` | Standard `reachable.ci.proof_page` output with branch, commit, run, PR, release blockers, defended items, and expandable evidence. |
| Release proof summary | `.reachable/ci-artifacts/release-proof/summary.json` | `Publish report` | Machine-readable data behind the release proof page. |
| Reachable JSON report | `.reachable/ci-artifacts/reachable-report.json` | `Publish report`, when export succeeds | Structured REACHABLE findings export for downstream review tools. |
| Reachable text summary | `.reachable/ci-artifacts/reachable-summary.txt` | `Publish report`, when export succeeds | Plain-text summary for quick artifact inspection. |
| Uploaded artifact bundle | GitHub Actions artifact `reachable-ci-artifacts` containing `.reachable/ci-artifacts/**` | `Upload Reachable artifacts` | Single downloadable bundle for reviewers and auditors. |

The workflow must not publish private remediation prompts, generated rules,
agent transcripts, raw witnesses, or local databases.

## Runbook

### Assess Only

Use this when you want a structured posture report without code changes.

```yaml
with:
  fail_on: exploitable
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
  fail_on: exploitable
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
  fail_on: exploitable
  remediate: true
  create_pr: true
  max_batches: 3
  rescan_strategy: each_batch
```

Expected result:

- remediation branch is pushed
- proof scan runs against that branch
- PR is opened with structured proof artifacts available for review

### Verify Existing Branch

Use this to prove a remediation branch again without changing code.

```yaml
with:
  target_branch: reachable-remediate-YYYYMMDD-HHMMSS-COMMIT
  fail_on: exploitable
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
| `ai_mode=openai-codex requires OPENAI_API_KEY` | Missing provider secret. | Add `OPENAI_API_KEY` to repository or organization Actions secrets. |
| PR branch pushed but no PR opened | GitHub Actions cannot create PRs. | Enable "Allow GitHub Actions to create and approve pull requests" and `pull-requests: write`. |
| Proof page reports blockers after remediation | The agent fixed only part of the queue or a finding needs manual review. | Review the branch and proof summary; rerun with more batches only if the remaining item is safe to automate. |
| Project tests did not run inside Reachable | The reusable workflow does not execute project test commands. | Use the remediation prompt, local release harnesses, and the application's normal CI/branch protection for language-specific validation. |

## SDK Boundary

The reusable workflow is intentionally thin. Standard behavior belongs in the
Reachable wheel under `reachable.ci`, including:

- workflow generation
- settings and secret doctor output
- cache/install evidence
- structured proof gates
- release proof pages
- expandable structured evidence paths / simple call graph rows
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
  --body "Reachable remediation branch with structured proof artifacts."
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
