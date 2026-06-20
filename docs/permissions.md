# GitHub Permissions

Reachable CI uses two different permission planes.

## Workflow Control

The GitHub Actions `GITHUB_TOKEN` controls CI operations:

- checkout
- branch push
- artifact upload
- Pages/report publication
- SARIF compatibility upload
- pull request creation

Required workflow permissions:

```yaml
permissions:
  contents: write
  pull-requests: write
  security-events: write
  actions: write
  pages: write
  id-token: write
```

Repository settings must also allow:

- workflow read/write permissions
- GitHub Actions creating pull requests
- the reusable workflow from `sthenos-security/reach-ci-github`

## Reachable Product Tokens

Reachable tokens are separate from workflow control:

| Secret | Purpose |
|--------|---------|
| `REACHABLE_API_KEY` | Optional product/cloud licensing and enrichment. |
| `REACHABLE_GITHUB_TOKEN` | Optional GitHub metadata/package enrichment for the scanner. |
| `MCP_GITHUB_TOKEN` | Recommended read-only GitHub source token for MCP GitHub cloning and package git clone fallback. Use a fine-grained PAT with `Contents: Read-only` on the repos Reachable should inspect. |
| `OPENAI_API_KEY` | Required for the default Codex/OpenAI lane in customer-facing runs. |
| `ANTHROPIC_API_KEY` | Required for the Claude/Anthropic lane in customer-facing runs. |
| `REACHABLE_COPILOT_USER_TOKEN` | Required only for `ai_mode=copilot-github`; used to dispatch GitHub Copilot issues/tasks. |
| `COPILOT_MCP_REACHABLE_TOKEN` | Optional Copilot Agents secret for read-only REACHABLE MCP context. Must be configured in the Copilot Agents secret plane, not only as an Actions secret. |

Create `MCP_GITHUB_TOKEN` at
<https://github.com/settings/personal-access-tokens/new>. Select the user or
organization **Resource owner** for the source repos, choose **Only select
repositories** or **All repositories** as appropriate, and grant only
**Repository permissions -> Contents: Read-only**. GitHub adds **Metadata:
Read-only** automatically. Do not grant write, pull request, workflow,
administration, or secret permissions to this token.

Do not use Reachable scanner tokens to create branches or PRs. That is the
workflow token's job.

For `ai_mode=copilot-github`, the workflow dispatches async Copilot tasks from
reachable high/critical DB-backed scan evidence and exits. A Copilot PR is not
considered fixed until a separate REACHABLE verification pass records proof for
the linked task.
