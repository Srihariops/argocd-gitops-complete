# 🤖 08 · Image Updater (ECR → Git → Argo CD)

> [!TIP]
> Jenkins pushes an image. **Image Updater** notices the new tag and updates the deployment for you. You choose **three things**: *where to write the tag*, *how to pick the tag*, *how to log in to ECR*.

## 1. What & why
**Use case:** Jenkins builds `fcoos/posts:007` → no one edits YAML → the app rolls out `007` by itself.

## 2. Architecture
```mermaid
flowchart LR
  J[Jenkins CI] -->|docker push :007| ECR[(AWS ECR)]
  subgraph Cluster
    IU[Image Updater] -->|"every ~2 min: list tags"| ECR
    Login[ECR login token<br/>12 h life] -.refreshed by.-> CJ[CronJob / script / IRSA]
    IU -->|reads| Login
  end
  IU -->|"A · write-back = git: commit newTag"| Git[(GitOps repo)]
  IU -->|"B · write-back = argocd: parameter override"| App[Application]
  Git --> Argo[Argo CD] --> K8s[Kubernetes pods pull image from ECR]
  App --> Argo
```

## 3. Decisions at a glance
| # | Decision | Options |
|---|---|---|
| 1 | How is it configured? | **ImageUpdater CR** (v1, recommended) · Annotations on the Application (legacy v0.x) |
| 2 | Where is the new tag written? | **Git** (production) · **Argo CD** live state (labs) |
| 3 | Which tag counts as newest? | `semver` · `newest-build` · `digest` · `alphabetical` |
| 4 | How does Image Updater log in to ECR? | A · access key + host cron · B · access key + in-cluster CronJob · **C · IAM role (IRSA)** · D · registries config styles · E · `.docker/config.json` |
| 5 | How does it log in to Git (git write-back)? | HTTPS token · SSH key |
| 6 | How do pods pull images? | pull Secret · ServiceAccount pull secret · **node IAM role** (no secret) |

## 4. Key values
| Key | Meaning | Example |
|---|---|---|
| `spec.namespace` | Where Applications live | `argocd` |
| `writeBackConfig.method` | `git:secret:<ns>/<secret>` or `argocd` | `git:secret:argocd/argocd-image-updater-git-creds` |
| `gitConfig.branch` | Branch to commit to | `main` |
| `gitConfig.writeBackTarget` | `kustomization` or `helmvalues:/path` | `kustomization` |
| `commonUpdateSettings.updateStrategy` | How to choose the new tag | `newest-build` |
| `allowTags` / `ignoreTags` | Filter tags with regex | `regexp:^[0-9]{3}$` |
| `applicationRefs[].namePattern` | Which Applications | `fcoos-*` |
| `images[].alias` / `imageName` | Short name / full image **without tag** | `...ecr.../fcoos/posts` |
| `credentials` (registries.conf) | How to authenticate | `pullsecret:argocd/argocd-image-updater-secret` |
| `credsexpire` | Reload credentials after | `10h` |

## 5. Install
```bash
# check the project docs for the current manifest/Helm chart of your version
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/config/install.yaml
# or Helm:  helm install argocd-image-updater argo/argocd-image-updater -n argocd
kubectl -n argocd get pods | grep image-updater
```

## 6. Decision 1 · Config style
<details>
<summary>📄 <b>imageupdater-git.yaml</b> — ImageUpdater CR, write-back git to kustomization (production).</summary>

```yaml
# ======================================================================
# FILE   : imageupdater-git.yaml
# PURPOSE: ImageUpdater CR, write-back git to kustomization (production).
# APPLY  : kubectl apply -f imageupdater-git.yaml
# ======================================================================
# WRITE-BACK = GIT (recommended for production). The new tag is committed to the repo.
apiVersion: argocd-image-updater.argoproj.io/v1alpha1
kind: ImageUpdater
metadata:
  name: fcoos-image-updater
  namespace: argocd
spec:
  namespace: argocd                       # namespace where the Applications live
  writeBackConfig:
    method: "git:secret:argocd/argocd-image-updater-git-creds"   # git:secret:<namespace>/<secret-with-username+password or sshPrivateKey>
    gitConfig:
      branch: main                        # branch to commit to (use master if that is yours)
      writeBackTarget: kustomization      # edit images: in kustomization.yaml of the Application path
      # repository: https://github.com/<org>/<gitops-repo>.git   # optional: if different from the Application source
  commonUpdateSettings:
    updateStrategy: newest-build          # semver | digest | newest-build | alphabetical
    forceUpdate: false
    allowTags: "regexp:^[0-9]{3}$"        # only 3-digit Jenkins tags 001..999
    # ignoreTags: ["latest", "regexp:.*-rc.*"]
    # pullSecret: "pullsecret:argocd/argocd-image-updater-secret"   # registry login (verify field name in your version)
  applicationRefs:
    - namePattern: fcoos-insights         # Application name (wildcards ok: "fcoos-*")
      images:
        - alias: fcoos-frontend           # any short unique name
          imageName: <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/fcoos/frontend   # no tag
        - alias: fcoos-posts
          imageName: <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/fcoos/posts
```

</details>
<details>
<summary>📄 <b>imageupdater-annotations-legacy.yaml</b> — Legacy: everything as annotations on the Application.</summary>

```yaml
# ======================================================================
# FILE   : imageupdater-annotations-legacy.yaml
# PURPOSE: Legacy: everything as annotations on the Application.
# APPLY  : annotate your Application
# ======================================================================
# LEGACY STYLE (Image Updater v0.x): configuration as ANNOTATIONS on the Application. No ImageUpdater CR.
# Still common in older clusters. New installs should use the CR files in this folder.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: fcoos-insights
  namespace: argocd
  annotations:
    argocd-image-updater.argoproj.io/image-list: |
      fe=<ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/fcoos/frontend,
      posts=<ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/fcoos/posts
    argocd-image-updater.argoproj.io/fe.update-strategy: newest-build
    argocd-image-updater.argoproj.io/fe.allow-tags: regexp:^[0-9]{3}$
    argocd-image-updater.argoproj.io/posts.update-strategy: newest-build
    argocd-image-updater.argoproj.io/write-back-method: git:secret:argocd/argocd-image-updater-git-creds
    argocd-image-updater.argoproj.io/git-branch: main
    argocd-image-updater.argoproj.io/write-back-target: kustomization
    # Helm charts: argocd-image-updater.argoproj.io/fe.helm.image-name: image.repository  (+ .helm.image-tag)
    # Registry login for ECR: argocd-image-updater.argoproj.io/fe.pull-secret: pullsecret:argocd/argocd-image-updater-secret
spec:
  project: myargoproject-dev
  source:
    repoURL: https://github.com/<org>/<gitops-repo>.git
    targetRevision: main
    path: k8-manifest
  destination: {server: https://kubernetes.default.svc, namespace: fcoos}
  syncPolicy:
    automated: {prune: true, selfHeal: true}
```

</details>

## 7. Decision 2 · Write-back method
| | **git** | **argocd** |
|---|---|---|
| Tag saved in Git | ✅ | ❌ (live only) |
| Survives app recreate | ✅ | ❌ |
| Audit / easy rollback | ✅ `git revert` | ❌ |
| Needs Git write token | yes | no |
| Use for | **production** | lab/dev |

```mermaid
flowchart LR
  New[new tag 008] --> M{method}
  M -->|git| C[commit kustomization.yaml or values file] --> Sync[Argo CD syncs from Git]
  M -->|argocd| P[set image parameter on Application] --> Sync2[Argo CD syncs live override]
```
<details>
<summary>📄 <b>imageupdater-argocd.yaml</b> — Write-back to Argo CD only (no Git commit).</summary>

```yaml
# ======================================================================
# FILE   : imageupdater-argocd.yaml
# PURPOSE: Write-back to Argo CD only (no Git commit).
# APPLY  : kubectl apply -f imageupdater-argocd.yaml
# ======================================================================
# WRITE-BACK = ARGOCD. The tag is set as a parameter override on the LIVE Application. Nothing is committed.
# Good for labs/dev. Weakness: if the Application is deleted/recreated the override is lost, Git does not show the tag.
apiVersion: argocd-image-updater.argoproj.io/v1alpha1
kind: ImageUpdater
metadata:
  name: dev-image-updater
  namespace: argocd
spec:
  namespace: argocd
  writeBackConfig:
    method: argocd                        # no Git credentials needed
  commonUpdateSettings:
    updateStrategy: newest-build
    allowTags: "regexp:^[0-9]{3}$"
  applicationRefs:
    - namePattern: mygitops-application-dev-first
      images:
        - alias: nginx
          imageName: <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/nginx
```

</details>
<details>
<summary>📄 <b>imageupdater-git-helm.yaml</b> — Git write-back into a Helm values file.</summary>

```yaml
# ======================================================================
# FILE   : imageupdater-git-helm.yaml
# PURPOSE: Git write-back into a Helm values file.
# APPLY  : kubectl apply -f imageupdater-git-helm.yaml
# ======================================================================
# WRITE-BACK = GIT for a HELM chart: the tag is written into a values file instead of kustomization.yaml.
apiVersion: argocd-image-updater.argoproj.io/v1alpha1
kind: ImageUpdater
metadata:
  name: web-helm-updater
  namespace: argocd
spec:
  namespace: argocd
  writeBackConfig:
    method: "git:secret:argocd/argocd-image-updater-git-creds"
    gitConfig:
      branch: main
      writeBackTarget: "helmvalues:/envs/dev/image-values.yaml"   # file (path from repo root) the updater creates/edits
  commonUpdateSettings:
    updateStrategy: semver
    allowTags: "regexp:^v[0-9]+\\.[0-9]+\\.[0-9]+$"
  applicationRefs:
    - namePattern: web-helm-git
      images:
        - alias: web
          imageName: <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/web
          # Tell it which Helm keys hold the image name and tag in your chart:
          manifestTargets:
            helm:
              name: image.repository
              tag: image.tag
```

</details>
<details>
<summary>📄 <b>kustomization-example.yaml</b> — The kustomization.yaml that the updater edits.</summary>

```yaml
# ======================================================================
# FILE   : kustomization-example.yaml
# PURPOSE: The kustomization.yaml that the updater edits.
# APPLY  : commit to your app folder
# ======================================================================
# Lives in the app folder (e.g. k8-manifest/kustomization.yaml). Image Updater edits the images: block.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - posts.yaml
  - frontend.yaml
images:                                  # one entry per image in ImageUpdater (same name, NO tag in name)
  - name: <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/fcoos/frontend
    newTag: "001"                        # keep quotes: "001" must stay a string
  - name: <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/fcoos/posts
    newTag: "001"
```

</details>
<details>
<summary>📄 <b>git-creds-secrets.yaml</b> — Git login to push (HTTPS token or SSH key).</summary>

```yaml
# ======================================================================
# FILE   : git-creds-secrets.yaml
# PURPOSE: Git login to push (HTTPS token or SSH key).
# APPLY  : kubectl apply -f git-creds-secrets.yaml
# ======================================================================
# Git login used by Image Updater to PUSH the tag (needs WRITE; Argo CD itself only needs read).
# Option 1: HTTPS username + token (fine-grained PAT: Contents Read and write on the GitOps repo only)
apiVersion: v1
kind: Secret
metadata:
  name: argocd-image-updater-git-creds    # referenced as git:secret:argocd/argocd-image-updater-git-creds
  namespace: argocd
type: Opaque
stringData:
  username: <github-username>
  password: <TOKEN_WITH_WRITE>
---
# Option 2: SSH deploy key with WRITE access (use git:secret:argocd/argocd-image-updater-git-ssh and the repo SSH URL)
apiVersion: v1
kind: Secret
metadata:
  name: argocd-image-updater-git-ssh
  namespace: argocd
type: Opaque
stringData:
  sshPrivateKey: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    <paste key>
    -----END OPENSSH PRIVATE KEY-----
```

</details>

## 8. Decision 3 · Update strategy
| Strategy | Picks | Use with |
|---|---|---|
| `semver` | highest `v1.2.3` | release tags |
| `newest-build` | most recently pushed tag | Jenkins numbers `001..999` |
| `digest` | new digest of one mutable tag | `latest` |
| `alphabetical` | last in sort order | date tags |

<details>
<summary>📄 <b>imageupdater-strategies.yaml</b> — All four strategies side by side.</summary>

```yaml
# ======================================================================
# FILE   : imageupdater-strategies.yaml
# PURPOSE: All four strategies side by side.
# APPLY  : kubectl apply -f imageupdater-strategies.yaml
# ======================================================================
# One file, four strategies. Choose per image with commonUpdateSettings on the image.
apiVersion: argocd-image-updater.argoproj.io/v1alpha1
kind: ImageUpdater
metadata:
  name: strategies-demo
  namespace: argocd
spec:
  namespace: argocd
  writeBackConfig:
    method: "git:secret:argocd/argocd-image-updater-git-creds"
    gitConfig: {branch: main, writeBackTarget: kustomization}
  applicationRefs:
    - namePattern: demo-*
      images:
        - alias: semver-img                 # releases like v1.4.2: picks the HIGHEST version
          imageName: <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/a
          commonUpdateSettings:
            updateStrategy: semver
            allowTags: "regexp:^v[0-9]+\\.[0-9]+\\.[0-9]+$"
        - alias: build-img                  # Jenkins build numbers: picks the most recently PUSHED
          imageName: <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/b
          commonUpdateSettings:
            updateStrategy: newest-build
            allowTags: "regexp:^[0-9]{3}$"
        - alias: digest-img                 # mutable tag (e.g. "latest"): redeploys when the digest changes
          imageName: <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/c:latest
          commonUpdateSettings:
            updateStrategy: digest
        - alias: date-img                   # tags like 2026-11-12: last in alphabetical order
          imageName: <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/d
          commonUpdateSettings:
            updateStrategy: alphabetical
            allowTags: "regexp:^[0-9]{4}-[0-9]{2}-[0-9]{2}$"
```

</details>

## 9. Decision 4 · ECR login (the part that breaks most)
ECR passwords **expire after 12 hours**, so something must refresh them.

```mermaid
flowchart TD
  Q{On EKS?} -->|yes| C[C · IAM role IRSA / Pod Identity<br/>no keys at all]
  Q -->|no / small lab| K{Where to run the refresh?}
  K -->|a server you own| A[A · host cron + access key]
  K -->|inside cluster| B[B · CronJob + access key]
  Other[Docker Hub / GHCR / static token] --> E[E · .docker/config.json secret]
```
| | A · host cron | B · CronJob + keys | **C · CronJob + IRSA** | D · registries styles | E · `.docker` file |
|---|---|---|---|---|---|
| Static AWS keys | yes | yes | **no** | depends | no (token inside) |
| Runs in cluster | no | yes | yes | - | no |
| Rotation burden | high | medium | **none** | - | high for ECR |
| Best for | quick start | clusters off AWS | **EKS production** | choose how updater reads | non-ECR registries |

### A · Access keys + host cron
<details>
<summary>📄 <b>ecr-A1-aws-keys-secret.yaml</b> — IAM user keys stored as a Secret.</summary>

```yaml
# ======================================================================
# FILE   : ecr-A1-aws-keys-secret.yaml
# PURPOSE: IAM user keys stored as a Secret.
# APPLY  : kubectl apply -f ecr-A1-aws-keys-secret.yaml
# ======================================================================
# ECR LOGIN, STEP 1 for access-key methods: IAM user keys stored as a Secret.
# IAM policy for this user (least privilege): ecr:GetAuthorizationToken (resource *),
#   ecr:BatchGetImage, ecr:GetDownloadUrlForLayer, ecr:DescribeImages, ecr:ListImages on your repos.
apiVersion: v1
kind: Secret
metadata:
  name: aws-ecr-credentials
  namespace: argocd
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: "<AKIA...>"
  AWS_SECRET_ACCESS_KEY: "<secret>"
  AWS_DEFAULT_REGION: ap-south-1          # MUST equal the region in your image URL
```

</details>
<details>
<summary>📄 <b>ecr-A2-host-cron-refresh.sh</b> — Script for crontab: new token into two docker-registry secrets.</summary>

```bash
#!/bin/bash
# ======================================================================
# FILE   : ecr-A2-host-cron-refresh.sh
# PURPOSE: Script for crontab: new token into two docker-registry secrets.
# APPLY  : crontab: 0 */6 * * * /bin/bash <path>
# ======================================================================
# Refreshes ECR login tokens (they expire every 12h) into Kubernetes docker-registry Secrets.
# Run from cron every 6h (see bottom). Needs: kubectl, aws cli.
set -Eeuo pipefail

# ---------------- CONFIG: edit these ----------------
AWS_NAMESPACE="argocd"                 # where the AWS key secret lives
AWS_SECRET="aws-ecr-credentials"       # secret with AWS_ACCESS_KEY_ID etc. (secrets.yaml, Secret A)
ECR_REGISTRY="<ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com"   # MUST match region/account of your images

ARGO_NAMESPACE="argocd"                # Image Updater reads this secret
ARGO_SECRET="argocd-image-updater-secret"
APP_NAMESPACE="fcoos"                  # app namespace; pods use this as imagePullSecret
APP_SECRET="ecr-pull-secret"
# -----------------------------------------------------

for cmd in kubectl aws base64; do
  command -v "$cmd" >/dev/null || { echo "ERROR: $cmd not found"; exit 1; }
done

get() { kubectl get secret "$AWS_SECRET" -n "$AWS_NAMESPACE" -o jsonpath="{.data.$1}" | base64 -d; }
export AWS_ACCESS_KEY_ID="$(get AWS_ACCESS_KEY_ID)"
export AWS_SECRET_ACCESS_KEY="$(get AWS_SECRET_ACCESS_KEY)"
export AWS_DEFAULT_REGION="$(get AWS_DEFAULT_REGION)"

[[ -n "$AWS_ACCESS_KEY_ID" && -n "$AWS_SECRET_ACCESS_KEY" && -n "$AWS_DEFAULT_REGION" ]] || { echo "ERROR: AWS values missing"; exit 1; }
trap 'unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION ECR_TOKEN' EXIT

aws sts get-caller-identity >/dev/null && echo "AWS auth OK (region $AWS_DEFAULT_REGION)"
ECR_TOKEN="$(aws ecr get-login-password --region "$AWS_DEFAULT_REGION")"

update_ecr_secret() {                  # $1=namespace  $2=secret name
  kubectl create secret docker-registry "$2" -n "$1" \
    --docker-server="$ECR_REGISTRY" --docker-username=AWS --docker-password="$ECR_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "Updated: $1/$2"
}
update_ecr_secret "$ARGO_NAMESPACE" "$ARGO_SECRET"   # for Image Updater
update_ecr_secret "$APP_NAMESPACE"  "$APP_SECRET"    # for pods pulling images
echo "Done at $(date)"

# ---------------- SETUP ----------------
# mkdir -p ~/awsecr && chmod 700 ~/awsecr/refresh-ecr-secrets.sh
# bash ~/awsecr/refresh-ecr-secrets.sh                      # test once
# crontab -e   ->  0 */6 * * * /bin/bash ~/awsecr/refresh-ecr-secrets.sh >> ~/awsecr/refresh.log 2>&1
# Your Deployments must list:  imagePullSecrets: [{name: ecr-pull-secret}]
```

</details>

### B · In-cluster CronJob with access keys
<details>
<summary>📄 <b>ecr-B-cronjob-access-key.yaml</b> — ServiceAccount, Roles, CronJob (every 6 h).</summary>

```yaml
# ======================================================================
# FILE   : ecr-B-cronjob-access-key.yaml
# PURPOSE: ServiceAccount, Roles, CronJob (every 6 h).
# APPLY  : kubectl apply -f ecr-B-cronjob-access-key.yaml
# ======================================================================
# APPROACH B: in-cluster CronJob + access keys. Replaces the laptop/server cron. Refreshes every 6 h.
apiVersion: v1
kind: ServiceAccount
metadata: {name: ecr-token-refresher, namespace: argocd}
---
# Permission to write the two docker-registry Secrets (one Role per namespace it touches)
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: ecr-token-refresher, namespace: argocd}
rules:
  - apiGroups: [""]
    resources: [secrets]
    verbs: [get, create, patch, update]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: ecr-token-refresher, namespace: argocd}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: Role, name: ecr-token-refresher}
subjects: [{kind: ServiceAccount, name: ecr-token-refresher, namespace: argocd}]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: ecr-token-refresher, namespace: fcoos}      # the APP namespace that needs ecr-pull-secret
rules:
  - apiGroups: [""]
    resources: [secrets]
    verbs: [get, create, patch, update]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: ecr-token-refresher, namespace: fcoos}
roleRef: {apiGroup: rbac.authorization.k8s.io, kind: Role, name: ecr-token-refresher}
subjects: [{kind: ServiceAccount, name: ecr-token-refresher, namespace: argocd}]
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: ecr-token-refresh
  namespace: argocd
spec:
  schedule: "0 */6 * * *"                 # every 6 hours (token lives 12 h)
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 1
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        spec:
          serviceAccountName: ecr-token-refresher
          restartPolicy: OnFailure
          containers:
            - name: refresh
              image: alpine/k8s:1.30.2    # any image that has BOTH kubectl and aws-cli
              envFrom:
                - secretRef: {name: aws-ecr-credentials}   # AWS_ACCESS_KEY_ID / SECRET / REGION
              env:
                - {name: ECR_REGISTRY, value: "<ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com"}
              command: [sh, -c]
              args:
                - |
                  set -e
                  TOKEN=$(aws ecr get-login-password --region "$AWS_DEFAULT_REGION")
                  for t in argocd/argocd-image-updater-secret fcoos/ecr-pull-secret; do
                    ns=${t%/*}; name=${t#*/}
                    kubectl create secret docker-registry "$name" -n "$ns" \
                      --docker-server="$ECR_REGISTRY" --docker-username=AWS --docker-password="$TOKEN" \
                      --dry-run=client -o yaml | kubectl apply -f -
                    echo "updated $ns/$name"
                  done
```

</details>

### C · In-cluster CronJob with IAM role (recommended on EKS)
<details>
<summary>📄 <b>ecr-C-cronjob-irsa.yaml</b> — Same CronJob, IAM role instead of keys.</summary>

```yaml
# ======================================================================
# FILE   : ecr-C-cronjob-irsa.yaml
# PURPOSE: Same CronJob, IAM role instead of keys.
# APPLY  : kubectl apply -f ecr-C-cronjob-irsa.yaml
# ======================================================================
# APPROACH C (BEST on EKS): same CronJob but NO access keys. The pod gets AWS permissions from an IAM ROLE (IRSA).
# Setup once:
#   1) IAM role with the ECR policy (ecr:GetAuthorizationToken) and a trust policy for this ServiceAccount
#      (eksctl create iamserviceaccount --cluster <c> --namespace argocd --name ecr-token-refresher \
#         --attach-policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/ecr-token --approve)
#   2) Keep the Role/RoleBinding objects from ecr-B-cronjob-access-key.yaml (kubectl permissions are separate)
# EKS Pod Identity works the same way: associate the role with the ServiceAccount, no annotation needed.
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ecr-token-refresher
  namespace: argocd
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<ACCOUNT_ID>:role/ecr-token-refresher   # IRSA link
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: ecr-token-refresh
  namespace: argocd
spec:
  schedule: "0 */6 * * *"
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: ecr-token-refresher     # AWS creds injected automatically, nothing in env
          restartPolicy: OnFailure
          containers:
            - name: refresh
              image: alpine/k8s:1.30.2
              env:
                - {name: AWS_DEFAULT_REGION, value: ap-south-1}
                - {name: ECR_REGISTRY, value: "<ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com"}
              command: [sh, -c]
              args:
                - |
                  set -e
                  TOKEN=$(aws ecr get-login-password)
                  for t in argocd/argocd-image-updater-secret fcoos/ecr-pull-secret; do
                    ns=${t%/*}; name=${t#*/}
                    kubectl create secret docker-registry "$name" -n "$ns" \
                      --docker-server="$ECR_REGISTRY" --docker-username=AWS --docker-password="$TOKEN" \
                      --dry-run=client -o yaml | kubectl apply -f -
                  done
```

</details>

### D · Registries config (how the updater reads the login)
<details>
<summary>📄 <b>ecr-D-registries-config.yaml</b> — registries.conf with 3 credential styles.</summary>

```yaml
# ======================================================================
# FILE   : ecr-D-registries-config.yaml
# PURPOSE: registries.conf with 3 credential styles.
# APPLY  : kubectl apply -f ecr-D-registries-config.yaml
# ======================================================================
# TELL IMAGE UPDATER HOW TO LOG IN TO ECR. Pick ONE credentials style (uncomment one line).
# NOTE: ConfigMap/key names can differ by Image Updater version. Check the docs of YOUR version.
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-image-updater-config
  namespace: argocd
data:
  registries.conf: |
    registries:
      - name: ECR
        api_url: https://<ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com
        prefix: <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com
        ping: yes
        insecure: no
        # STYLE 1 (works with approaches A/B/C): read the docker-registry Secret the CronJob keeps fresh
        credentials: pullsecret:argocd/argocd-image-updater-secret
        # STYLE 2: run a script that prints "AWS:<token>" (needs aws-cli inside the updater image + IRSA on its pod)
        # credentials: ext:/scripts/ecr-login.sh
        # STYLE 3: plain secret with a key holding "user:password"
        # credentials: secret:argocd/ecr-creds#creds
        credsexpire: 10h                  # re-read before the 12 h token expires
```

</details>
<details>
<summary>📄 <b>ecr-D2-ext-script.sh</b> — ext: script that prints AWS:token (needs aws-cli in the updater image).</summary>

```bash
#!/bin/sh
# ======================================================================
# FILE   : ecr-D2-ext-script.sh
# PURPOSE: ext: script that prints AWS:token (needs aws-cli in the updater image).
# APPLY  : mount as /scripts/ecr-login.sh
# ======================================================================
# STYLE 2 helper: Image Updater runs this and reads "username:password" from stdout.
# Requires aws-cli in the Image Updater container (build a small custom image) and an IAM role on its ServiceAccount.
# Mount it via a ConfigMap at /scripts/ecr-login.sh (mode 0755) and set credentials: ext:/scripts/ecr-login.sh
echo "AWS:$(aws ecr get-login-password --region ap-south-1)"
```

</details>

### E · `.docker/config.json` secret
<details>
<summary>📄 <b>docker-config-from-file.sh</b> — Create a dockerconfigjson Secret from ~/.docker/config.json; credential-helper note.</summary>

```bash
#!/bin/sh
# ======================================================================
# FILE   : docker-config-from-file.sh
# PURPOSE: Create a dockerconfigjson Secret from ~/.docker/config.json; credential-helper note.
# APPLY  : run the commands
# ======================================================================
# APPROACH E: build the registry Secret from your ~/.docker/config.json (".docker" approach). Good for ANY registry.
# 1) log in once (this writes ~/.docker/config.json)
aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com
#    Docker Hub:  docker login        GHCR: echo $PAT | docker login ghcr.io -u <user> --password-stdin

# 2) turn the file into a Kubernetes pull Secret (works for pods AND for Image Updater pullsecret:)
kubectl create secret generic ecr-pull-secret -n fcoos \
  --from-file=.dockerconfigjson=$HOME/.docker/config.json \
  --type=kubernetes.io/dockerconfigjson
kubectl create secret generic argocd-image-updater-secret -n argocd \
  --from-file=.dockerconfigjson=$HOME/.docker/config.json \
  --type=kubernetes.io/dockerconfigjson

# 3) WARNING: the ECR token inside expires in 12 h. For ECR prefer approach B or C. Static registries (Docker Hub, GHCR) are fine.
# Credential-helper alternative (no expiry handling by you): install docker-credential-ecr-login and set
#   { "credHelpers": { "<ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com": "ecr-login" } }  in config.json (needs IAM on the machine/pod)
```

</details>

## 10. Decision 6 · Pods pulling from ECR
<details>
<summary>📄 <b>pod-pull-secret.yaml</b> — imagePullSecrets on ServiceAccount or Deployment; node-role alternative.</summary>

```yaml
# ======================================================================
# FILE   : pod-pull-secret.yaml
# PURPOSE: imagePullSecrets on ServiceAccount or Deployment; node-role alternative.
# APPLY  : kubectl apply -f pod-pull-secret.yaml
# ======================================================================
# How PODS use the pull secret. Two ways: per Deployment or on the ServiceAccount (all pods in the namespace).
apiVersion: v1
kind: ServiceAccount
metadata:
  name: default
  namespace: fcoos
imagePullSecrets:
  - name: ecr-pull-secret               # every pod using this ServiceAccount can pull from ECR
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: posts, namespace: fcoos}
spec:
  replicas: 1
  selector: {matchLabels: {app: posts}}
  template:
    metadata: {labels: {app: posts}}
    spec:
      imagePullSecrets:
        - name: ecr-pull-secret         # per-Deployment alternative
      containers:
        - name: posts
          image: <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/fcoos/posts   # tag replaced by kustomize images:
# NO SECRET NEEDED on EKS if the NODE IAM ROLE has AmazonEC2ContainerRegistryReadOnly (same account/region):
# kubelet pulls from ECR automatically. Image Updater still needs its own login to LIST tags.
```

</details>

## 11. Verify
```bash
kubectl -n argocd logs deploy/argocd-image-updater-controller -f      # look for "Successfully updated"
kubectl -n argocd get imageupdaters
kubectl -n argocd get cronjob ecr-token-refresh && kubectl -n argocd get jobs
git pull && git log -3          # commit "build: automatic update ..." (write-back git)
argocd app get fcoos-insights   # new image tag in the deployed parameters
```
**Test:** push tag `002` to ECR → wait a few minutes → see the commit → see pods roll.

## 12. Troubleshooting
| Symptom | Cause | Fix |
|---|---|---|
| `401` / `no basic auth credentials` | ECR token expired | check CronJob logs, run it once: `kubectl create job --from=cronjob/ecr-token-refresh test-1 -n argocd` |
| Nothing happens | tag regex, `namePattern`, or no `images:` entry | tags must match `allowTags`; name equals Application |
| `permission denied` pushing | token lacks write / protected branch | write token; allow the bot on `main` |
| Wrong region | URL, secret and `aws ecr` region differ | use one region/account everywhere |
| `ImagePullBackOff` in app pods | pods lack pull secret | [section 10](#10-decision-6--pods-pulling-from-ecr) |
| Update loop | CI reacts to bot commit | exclude Image Updater commits in CI |
| Helm app not updated | missing `manifestTargets` / values path | set image name/tag keys |

## 13. Checklist
- [ ] write-back **git** in production · [ ] `allowTags` set · [ ] ECR login via **IRSA** (or tested CronJob) · [ ] Git token is write-only to that one repo · [ ] pods have pull access · [ ] CI ignores bot commits
