# 🔑 05 · Repositories (connect Git and chart repos)

> [!WARNING]
> **Never paste a real token in a chat, an issue or Git.** If you did, revoke it now and make a new one. Argo CD only needs **read-only** access.

## 1. What & why
Argo CD must read your repo. Public repos need nothing. Private repos need a credential stored as a **Secret with label** `argocd.argoproj.io/secret-type`.

## 2. Architecture
```mermaid
flowchart LR
  S1[Secret: repository<br/>ONE repo] --> RS[repo-server]
  S2[Secret: repo-creds<br/>URL prefix template] --> RS
  RS -->|HTTPS token / SSH key / GitHub App| GH[(GitHub · GitLab · CodeCommit)]
  RS -->|Helm / OCI| CH[(Chart repo · ECR OCI)]
```

## 3. Key values
| Key | Meaning | Example |
|---|---|---|
| label `secret-type: repository` | Makes the Secret a repo credential | required |
| label `secret-type: repo-creds` | Credential **template** for all repos under a URL prefix | org URL |
| `type` | `git` or `helm` | `git` |
| `url` | Must equal `Application.source.repoURL` | `https://github.com/org/repo.git` |
| `username` / `password` | HTTPS token login | PAT |
| `sshPrivateKey` | SSH login | ed25519 key |
| `githubAppID` / `githubAppInstallationID` / `githubAppPrivateKey` | GitHub App login | - |
| `enableOCI` | Helm charts as OCI | `"true"` |
| `project` | Restrict this repo to one project | `myargoproject-dev` |

## 4. Choose your approach
| Method | Expiry | Best for | File |
|---|---|---|---|
| HTTPS + token (PAT) | yes (rotate) | quick start | `repo-https-token.yaml` |
| **SSH deploy key** | no | per-repo, read-only | `repo-ssh.yaml` |
| **GitHub App** | auto | organizations (recommended) | `repo-github-app.yaml` |
| AWS CodeCommit (IAM Git creds) | no | AWS-native repos | `repo-codecommit.yaml` |
| Private Helm repo | - | company charts | `repo-helm-private.yaml` |
| Helm OCI in ECR | 12 h | charts in ECR | `repo-oci-ecr-helm.yaml` |
| Credential template | - | many repos, one login | `repo-creds-template.yaml` |
| CLI / UI | - | tests | `repo-cli.sh` |

```mermaid
flowchart TD
  A{Where is the repo?} -->|GitHub org| B[GitHub App]
  A -->|GitHub single repo| C[SSH deploy key]
  A -->|CodeCommit| D[IAM Git creds]
  A -->|Helm charts| E[Helm repo / OCI]
  B --> F[Store secret encrypted: folder 15]
  C --> F
```

## 5. Approach A · HTTPS + token
<details>
<summary>📄 <b>repo-https-token.yaml</b> — Login for one private repo with a read-only token.</summary>

```yaml
# ======================================================================
# FILE   : repo-https-token.yaml
# PURPOSE: Login for one private repo with a read-only token.
# APPLY  : kubectl apply -f repo-https-token.yaml
# ======================================================================
# Tells Argo CD HOW to log in to ONE private Git repo.
# DO NOT commit real values. Use Sealed Secrets / External Secrets / SOPS.
apiVersion: v1
kind: Secret
metadata:
  name: repo-gitops-https                # any name (lowercase, no underscores)
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository   # THE KEY LABEL: without it Argo CD ignores this Secret
stringData:
  type: git                           # repository type
  name: gitops-repo                   # friendly name in the UI
  project: myargoproject-dev          # optional: only this project can use the repo. Remove = all projects
  url: https://github.com/<org>/<gitops-repo>.git   # must equal Application.spec.source.repoURL
  username: <github-username>
  password: <GITHUB_READ_ONLY_TOKEN>  # fine-grained PAT, Contents: read-only
  # insecure: "true"                  # only for self-signed TLS. NOT needed for GitHub
  # enableLfs: "true"                 # only if the repo uses Git LFS
```

</details>
<details>
<summary>📄 <b>repo-creds-template.yaml</b> — One credential reused for every repo under a prefix.</summary>

```yaml
# ======================================================================
# FILE   : repo-creds-template.yaml
# PURPOSE: One credential reused for every repo under a prefix.
# APPLY  : kubectl apply -f repo-creds-template.yaml
# ======================================================================
# ONE credential for every repo whose URL starts with the prefix below.
# Add each repo later in the UI/CLI without typing the password again.
apiVersion: v1
kind: Secret
metadata:
  name: github-org-creds
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repo-creds     # note: repo-creds (not repository)
stringData:
  type: git
  url: https://github.com/<org>                    # URL prefix
  username: <github-username>
  password: <GITHUB_READ_ONLY_TOKEN>
```

</details>

## 6. Approach B · SSH deploy key
<details>
<summary>📄 <b>repo-ssh.yaml</b> — SSH private key login.</summary>

```yaml
# ======================================================================
# FILE   : repo-ssh.yaml
# PURPOSE: SSH private key login.
# APPLY  : kubectl apply -f repo-ssh.yaml
# ======================================================================
# Approach: SSH deploy key (no expiry, read-only key per repo). Works with GitHub/GitLab/CodeCommit(SSH).
# 1) ssh-keygen -t ed25519 -f argocd-deploy-key -N ""    2) add argocd-deploy-key.pub as a READ-ONLY deploy key in the repo
apiVersion: v1
kind: Secret
metadata:
  name: repo-gitops-ssh
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: git@github.com:<org>/<gitops-repo>.git     # SSH URL (not https)
  sshPrivateKey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    <paste private key>
    -----END OPENSSH PRIVATE KEY-----
  # Host key trust: add the host to argocd-ssh-known-hosts-cm (GitHub's keys are built in)
  # insecureIgnoreHostKey: "true"                 # lab only
```

</details>

## 7. Approach C · GitHub App
<details>
<summary>📄 <b>repo-github-app.yaml</b> — App-based login, best for organizations.</summary>

```yaml
# ======================================================================
# FILE   : repo-github-app.yaml
# PURPOSE: App-based login, best for organizations.
# APPLY  : kubectl apply -f repo-github-app.yaml
# ======================================================================
# Approach: GitHub App (best for organizations: no personal user, higher rate limits, auto-rotating tokens)
# Create: GitHub Org -> Settings -> Developer settings -> GitHub Apps -> New. Permission: Contents = Read-only.
# Install the app on the GitOps repo. Note App ID and Installation ID. Generate a private key (.pem).
apiVersion: v1
kind: Secret
metadata:
  name: repo-gitops-ghapp
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: https://github.com/<org>/<gitops-repo>.git
  githubAppID: "<APP_ID>"
  githubAppInstallationID: "<INSTALLATION_ID>"
  githubAppPrivateKey: |
    -----BEGIN RSA PRIVATE KEY-----
    <paste .pem>
    -----END RSA PRIVATE KEY-----
  # githubAppEnterpriseBaseUrl: https://ghe.example.com/api/v3   # only for GitHub Enterprise
```

</details>

## 8. Approach D · AWS CodeCommit
<details>
<summary>📄 <b>repo-codecommit.yaml</b> — IAM HTTPS Git credentials.</summary>

```yaml
# ======================================================================
# FILE   : repo-codecommit.yaml
# PURPOSE: IAM HTTPS Git credentials.
# APPLY  : kubectl apply -f repo-codecommit.yaml
# ======================================================================
# Approach: AWS CodeCommit with IAM "HTTPS Git credentials" (IAM -> user -> Security credentials).
apiVersion: v1
kind: Secret
metadata:
  name: repo-codecommit
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: https://git-codecommit.ap-south-1.amazonaws.com/v1/repos/<repo-name>
  username: <iam-git-username-at-123456789012>     # generated by IAM, not your IAM user name
  password: <iam-git-password>
```

</details>

## 9. Approach E · Helm repos and OCI (ECR)
<details>
<summary>📄 <b>repo-helm-private.yaml</b> — Private Helm chart repository.</summary>

```yaml
# ======================================================================
# FILE   : repo-helm-private.yaml
# PURPOSE: Private Helm chart repository.
# APPLY  : kubectl apply -f repo-helm-private.yaml
# ======================================================================
# Approach: private Helm chart repository (ChartMuseum, Nexus, Artifactory, GitHub Pages with auth).
apiVersion: v1
kind: Secret
metadata:
  name: repo-helm-private
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: helm
  name: company-charts                  # REQUIRED for helm repos (used in Applications as repoURL + chart)
  url: https://charts.example.com
  username: <user>
  password: <password-or-token>
```

</details>
<details>
<summary>📄 <b>repo-oci-ecr-helm.yaml</b> — OCI charts in ECR (token refresh needed).</summary>

```yaml
# ======================================================================
# FILE   : repo-oci-ecr-helm.yaml
# PURPOSE: OCI charts in ECR (token refresh needed).
# APPLY  : kubectl apply -f repo-oci-ecr-helm.yaml
# ======================================================================
# Approach: Helm charts stored as OCI artifacts in AWS ECR.
# The ECR password expires in 12h -> refresh it with the same CronJob as folder 08 (write it into this Secret).
apiVersion: v1
kind: Secret
metadata:
  name: repo-ecr-oci
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: helm
  name: ecr-charts
  enableOCI: "true"                     # treat as an OCI registry
  url: <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com   # no https:// for OCI
  username: AWS
  password: "<output of aws ecr get-login-password --region ap-south-1>"
```

</details>

## 10. Approach F · CLI and UI
<details>
<summary>📄 <b>repo-cli.sh</b> — argocd repo add for every type.</summary>

```bash
#!/bin/sh
# ======================================================================
# FILE   : repo-cli.sh
# PURPOSE: argocd repo add for every type.
# APPLY  : sh repo-cli.sh
# ======================================================================
# Approach: CLI (stores the same Secret for you)
argocd repo add https://github.com/<org>/<repo>.git --username <user> --password <token> --project myargoproject-dev   # HTTPS
argocd repo add git@github.com:<org>/<repo>.git --ssh-private-key-path ~/.ssh/argocd-deploy-key                       # SSH
argocd repo add https://charts.example.com --type helm --name company-charts --username u --password p                 # Helm repo
argocd repo add <acct>.dkr.ecr.ap-south-1.amazonaws.com --type helm --name ecr-charts --enable-oci --username AWS --password "$(aws ecr get-login-password --region ap-south-1)"
argocd repocreds add https://github.com/<org> --username <user> --password <token>                                    # template for a whole org
argocd repo list        # Status must be Successful
# Test the same token outside Argo CD:  git ls-remote https://<user>:<token>@github.com/<org>/<repo>.git
```

</details>
**UI:** Settings → Repositories → **Connect repo** → choose method (HTTPS / SSH / GitHub App) → Connect.

## 11. Verify
```bash
argocd repo list                                   # Status: Successful
kubectl -n argocd get secrets -l argocd.argoproj.io/secret-type
```

## 12. Troubleshooting
| Symptom | Cause | Fix |
|---|---|---|
| Status Failed | wrong token/URL | `git ls-remote` with the same token |
| Secret ignored | label missing | add `argocd.argoproj.io/secret-type: repository` |
| App says repo not found | `url` differs (`.git`, case) | make them identical |
| SSH host key error | unknown host | add to `argocd-ssh-known-hosts-cm` |
| Helm OCI 401 | ECR token expired | refresh ([08](../08_image_updater/README.md)) |

## 13. Checklist
- [ ] Read-only credential · [ ] stored encrypted ([15](../15_secrets/README.md)) · [ ] old exposed tokens revoked · [ ] GitHub App or SSH for production
