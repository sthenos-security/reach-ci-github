# REACHABLE GitHub And GitLab Repositories

This file explains the public CI/CD repository layout. The GitHub and GitLab
sets are intentionally symmetrical: each ecosystem has a reusable toolkit, a
distribution/discovery surface, and a Go demo repo that covers both full
remediation and scan-only runs with remediation disabled.

## GitHub Repositories

| Repository | Primary role | Use this when |
|---|---|---|
| [`reach-testbed-github-marketplace`](https://github.com/sthenos-security/reach-testbed-github-marketplace) | GitHub Marketplace distribution surface plus the configurable root action. | You need the public GitHub Marketplace listing or a step-level `uses: sthenos-security/reach-testbed-github-marketplace@v1` action. |
| [`reach-ci-github`](https://github.com/sthenos-security/reach-ci-github) | Reusable GitHub Actions toolkit for production auto-remediation. | You want the recommended customer workflow with branch creation, proof scan, optional PR, artifacts, and Pages proof. |
| [`reach-testbed-github-go`](https://github.com/sthenos-security/reach-testbed-github-go) | Public GitHub demo repo. | You want runnable Codex and Claude demos, public source cloning, MCP GitHub cloning, git clone fallback, post-remediation proof, or a scan-only sample with remediation disabled. |

## GitLab Repositories

| Repository | Primary role | GitHub equivalent |
|---|---|---|
| [`reach-testbed-gitlab-catalog`](https://gitlab.com/sthenos-security-public/reach-testbed-gitlab-catalog) | GitLab CI/CD Catalog component plus full remediation demo. GitLab Catalog is the GitLab distribution surface; commercial partner routing is separate. | `reach-testbed-github-marketplace` |
| [`reach-ci-gitlab`](https://gitlab.com/sthenos-security-public/reach-ci-gitlab) | Reusable GitLab remediation toolkit. | `reach-ci-github` |
| [`reach-testbed-gitlab-go`](https://gitlab.com/sthenos-security-public/reach-testbed-gitlab-go) | Public GitLab demo repo. | `reach-testbed-github-go` |

## Architecture

The Marketplace/Catalog repositories are the discovery and onboarding
surfaces. The toolkit repositories contain the reusable CI implementation. The
Go demo repositories are the public runnable examples and validation targets.

Use the distribution surface first:

- GitHub: Marketplace action for discovery and step-level scan/remediation, or
  `reach-ci-github` reusable workflow for full production remediation.
- GitLab: Catalog component for the full pipeline.

For scan-only examples, use the same toolkit-backed Go demo repos with
remediation disabled. The older standalone scan demos are obsolete and are not
part of the supported public onboarding path.
