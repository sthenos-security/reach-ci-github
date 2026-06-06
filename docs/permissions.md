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
| `MCP_GITHUB_TOKEN` | Optional MCP context token. |
| `OPENAI_API_KEY` | Codex/OpenAI remediation lane. |
| `ANTHROPIC_API_KEY` | Claude/Anthropic remediation lane. |

Do not use Reachable scanner tokens to create branches or PRs. That is the
workflow token's job.

