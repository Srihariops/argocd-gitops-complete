# 10 · SSO + RBAC (Google Workspace)

> ### 🟢 Simple version
> **In one line:** Log in with Google. Your Google group decides what you can do.
> **Your goal:** Add a person to a Google group and permissions follow. No YAML change.
> **You will:** Create Google groups → Apply 4 files → Restart dex + server → Test can-i
> Need the full detail? Keep reading below. Otherwise jump to the files.


**Authentication** (who are you?) = `argocd-cm` (Dex Google connector).
**Authorization** (what can you do?) = `argocd-rbac-cm` (groups → roles → permissions).

```mermaid
sequenceDiagram
  participant U as User
  participant A as Argo CD
  participant D as Dex
  participant G as Google
  U->>A: Log in via Google
  A->>D: redirect
  D->>G: sign in
  D->>G: service account asks "which groups?"
  D-->>A: token + groups
  A->>A: match groups with g, lines in rbac-cm
  A-->>U: allowed UI/actions
```

**Golden rule:** permissions belong to *groups*; users are only added to groups in Google. New engineer = add to a Google group, no YAML change.

## Roles in this example
| Team | Google group | Role | Can do |
|---|---|---|---|
| DevOps | argocd-devops@ | `role:admin` | everything |
| SRE | argocd-sre@ | `role:sre` | view all, sync all, restart, logs |
| Junior DevOps | argocd-junior-devops@ | `role:junior-devops` | view all, sync/restart staging only, delete denied |
| Developer | argocd-developers@ | `role:developer` | view all, sync staging only |

## Steps
1. Google: create 4 groups, an OAuth Web client (redirect `https://argocd.example.com/api/dex/callback`), a service account with Admin SDK API + domain-wide delegation, scope `https://www.googleapis.com/auth/admin.directory.group.readonly`.
2. Apply: [sso-secret.yaml](sso-secret.yaml), [google-sa-secret.yaml](google-sa-secret.yaml), [argocd-cm.yaml](argocd-cm.yaml), [argocd-rbac-cm.yaml](argocd-rbac-cm.yaml).
3. Mount the service-account secret in Dex ([dex-mount-patch.yaml](dex-mount-patch.yaml)). With Helm, use `dex.volumes` / `dex.volumeMounts` instead.
4. `kubectl -n argocd rollout restart deploy argocd-dex-server argocd-server`
5. Test: `argocd account can-i sync applications 'staging/app'`. Log out/in after group changes.
6. Finally set `admin.enabled: "false"`.

> **Note:** `argocd-cm.yaml` / Helm `configs.cm` may be managed by Helm. If so, put these values in `values.yaml` or you will overwrite each other.

📖 The full detailed walk-through is your existing `sso/argocd-google-sso-rbac-guide.md`; keep it next to these files.

## Rules
- Multiple groups → permissions **add up**.
- `deny` always wins. `policy.default: ""` = no access by default.
- Group names are case-sensitive and must match Google exactly.
- Test any role with `argocd admin settings rbac can <role> sync applications 'prj/app' --policy-file policy.csv`.

## Google one-time setup (summary)
1. **Groups:** Admin Console → Directory → Groups: `argocd-devops@`, `argocd-sre@`, `argocd-junior-devops@`, `argocd-developers@`.
2. **OAuth client:** Cloud Console → Credentials → OAuth client ID → Web application, redirect `https://argocd.example.com/api/dex/callback`.
3. **Service account:** enable *Admin SDK API*, create a service account, create a **JSON key**, note its numeric *Client ID*.
4. **Domain-wide delegation:** Admin Console → Security → API controls → add that Client ID with scope `https://www.googleapis.com/auth/admin.directory.group.readonly`.
5. **Admin email:** pick a Workspace admin email for `domainToAdminEmail`.

## Daily operations (no YAML, no restart)
| Task | Do |
|---|---|
| New engineer joins SRE | Add to `argocd-sre@` group |
| Developer becomes SRE | Remove from developers, add to sre |
| Person leaves | Remove from all `argocd-*@` groups and suspend the account |
| New team | Create group, add to `groups:` in argocd-cm, add `p,` and `g,` lines |

Groups are copied into the token **at login**: after a change the user must log out and in again.


---

## Files in this guide

| # | File | Purpose | What you change |
|---|---|---|---|
| 1 | [`appprojects-staging-prod.yaml`](appprojects-staging-prod.yaml) | Creates projects staging and prod that the RBAC lines refer to. | Repo pattern and namespace patterns. |
| 2 | [`sso-secret.yaml`](sso-secret.yaml) | Google OAuth client ID and secret (the login button). | Client ID and secret. |
| 3 | [`google-sa-secret.yaml`](google-sa-secret.yaml) | Service account JSON key so Dex can read Workspace groups. | Paste the downloaded JSON as it is. |
| 4 | [`dex-mount-patch.yaml`](dex-mount-patch.yaml) | Mounts the key into the Dex pod at /tmp/oidc/serviceaccount.json. | Usually nothing. With Helm use dex.volumes instead. |
| 5 | [`argocd-cm.yaml`](argocd-cm.yaml) | AUTHENTICATION: URL and Google connector (domain, admin email, allowed groups). | Domain, admin email, group emails, URLs. |
| 6 | [`argocd-rbac-cm.yaml`](argocd-rbac-cm.yaml) | AUTHORIZATION: what each role can do and which group gets which role. | Group emails and permissions. |

---

## The files, with explanations

Every file has `#` comments on each important line. Replace anything in `<angle brackets>`.

### File 1: `appprojects-staging-prod.yaml`
**Purpose:** Creates projects staging and prod that the RBAC lines refer to.  
**What you change:** Repo pattern and namespace patterns.  
**Apply:** `kubectl apply -f appprojects-staging-prod.yaml`

```yaml
# ======================================================================
# FILE   : appprojects-staging-prod.yaml
# PURPOSE: Creates projects staging and prod that the RBAC lines refer to.
# CHANGE : Repo pattern and namespace patterns.
# APPLY  : kubectl apply -f appprojects-staging-prod.yaml
# ======================================================================
# RBAC lines like "staging/*" and "prod/*" refer to PROJECT NAMES.
# So for the SSO RBAC in this folder to work, your Applications must belong to projects called
# "staging" and "prod". (If you keep the names myargoproject-dev / myargoproject-prod from folder 03,
# change staging/* and prod/* in argocd-rbac-cm.yaml to those names instead.)
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: staging
  namespace: argocd                   # AppProjects always live in the argocd namespace
spec:
  description: Staging applications
  sourceRepos:
    - "https://github.com/<org>/*"    # only repos matching this pattern
  destinations:
    - server: https://kubernetes.default.svc
      namespace: "*-staging"          # only namespaces ending in -staging
---
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: prod
  namespace: argocd
spec:
  description: Production applications
  sourceRepos:
    - "https://github.com/<org>/*"
  destinations:
    - server: https://kubernetes.default.svc
      namespace: "*-prod"             # only namespaces ending in -prod
```

### File 2: `sso-secret.yaml`
**Purpose:** Google OAuth client ID and secret (the login button).  
**What you change:** Client ID and secret.  
**Apply:** `kubectl apply -f sso-secret.yaml`

```yaml
# ======================================================================
# FILE   : sso-secret.yaml
# PURPOSE: Google OAuth client ID and secret (the login button).
# CHANGE : Client ID and secret.
# APPLY  : kubectl apply -f sso-secret.yaml
# ======================================================================
apiVersion: v1
kind: Secret
metadata:
  name: argocd-sso-secret             # referenced in argocd-cm as $argocd-sso-secret:<key>
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: argocd # REQUIRED, otherwise Argo CD ignores it
type: Opaque
stringData:
  google.clientID: "<GOOGLE_OAUTH_CLIENT_ID>"
  google.clientSecret: "<GOOGLE_OAUTH_CLIENT_SECRET>"
```

### File 3: `google-sa-secret.yaml`
**Purpose:** Service account JSON key so Dex can read Workspace groups.  
**What you change:** Paste the downloaded JSON as it is.  
**Apply:** `kubectl apply -f google-sa-secret.yaml`

```yaml
# ======================================================================
# FILE   : google-sa-secret.yaml
# PURPOSE: Service account JSON key so Dex can read Workspace groups.
# CHANGE : Paste the downloaded JSON as it is.
# APPLY  : kubectl apply -f google-sa-secret.yaml
# ======================================================================
# Holds the service-account JSON key (downloaded from Google Cloud). Paste the file AS IS.
# Key name MUST be serviceaccount.json (it becomes the file name in the Dex pod).
apiVersion: v1
kind: Secret
metadata:
  name: argocd-google-sa
  namespace: argocd
type: Opaque
stringData:
  serviceaccount.json: |
    {
      "type": "service_account",
      "project_id": "<PROJECT_ID>",
      "private_key_id": "<KEY_ID>",
      "private_key": "-----BEGIN PRIVATE KEY-----\n<...>\n-----END PRIVATE KEY-----\n",
      "client_email": "<NAME>@<PROJECT_ID>.iam.gserviceaccount.com",
      "client_id": "<NUMERIC_CLIENT_ID>",
      "token_uri": "https://oauth2.googleapis.com/token"
    }
```

### File 4: `dex-mount-patch.yaml`
**Purpose:** Mounts the key into the Dex pod at /tmp/oidc/serviceaccount.json.  
**What you change:** Usually nothing. With Helm use dex.volumes instead.  
**Apply:** `kubectl -n argocd patch deploy argocd-dex-server --patch-file dex-mount-patch.yaml`

```yaml
# ======================================================================
# FILE   : dex-mount-patch.yaml
# PURPOSE: Mounts the key into the Dex pod at /tmp/oidc/serviceaccount.json.
# CHANGE : Usually nothing. With Helm use dex.volumes instead.
# APPLY  : kubectl -n argocd patch deploy argocd-dex-server --patch-file dex-mount-patch.yaml
# ======================================================================
# Mounts the service account key into Dex at /tmp/oidc/serviceaccount.json
apiVersion: apps/v1
kind: Deployment
metadata:
  name: argocd-dex-server
  namespace: argocd
spec:
  template:
    spec:
      volumes:
        - name: google-sa
          secret:
            secretName: argocd-google-sa
      containers:
        - name: dex
          volumeMounts:
            - name: google-sa
              mountPath: /tmp/oidc
              readOnly: true
```

### File 5: `argocd-cm.yaml`
**Purpose:** AUTHENTICATION: URL and Google connector (domain, admin email, allowed groups).  
**What you change:** Domain, admin email, group emails, URLs.  
**Apply:** `kubectl apply -f argocd-cm.yaml`

```yaml
# ======================================================================
# FILE   : argocd-cm.yaml
# PURPOSE: AUTHENTICATION: URL and Google connector (domain, admin email, allowed groups).
# CHANGE : Domain, admin email, group emails, URLs.
# APPLY  : kubectl apply -f argocd-cm.yaml
# ======================================================================
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-cm
    app.kubernetes.io/part-of: argocd
data:
  url: https://argocd.example.com       # same host as the Google redirect URI
  admin.enabled: "true"                 # set "false" once SSO admin login is confirmed
  dex.config: |
    connectors:
      - type: google
        id: google
        name: Google                    # text on the login button
        config:
          clientID: $argocd-sso-secret:google.clientID
          clientSecret: $argocd-sso-secret:google.clientSecret
          redirectURI: https://argocd.example.com/api/dex/callback
          hostedDomains:
            - example.com               # only your Workspace domain may log in
          serviceAccountFilePath: /tmp/oidc/serviceaccount.json
          domainToAdminEmail:
            example.com: admin@example.com    # admin the service account impersonates
          groups:                       # allow-list: users in none of these are refused
            - argocd-devops@example.com
            - argocd-sre@example.com
            - argocd-junior-devops@example.com
            - argocd-developers@example.com
          scopes:
            - profile
            - email
            - https://www.googleapis.com/auth/admin.directory.group.readonly
```

### File 6: `argocd-rbac-cm.yaml`
**Purpose:** AUTHORIZATION: what each role can do and which group gets which role.  
**What you change:** Group emails and permissions.  
**Apply:** `kubectl apply -f argocd-rbac-cm.yaml`

```yaml
# ======================================================================
# FILE   : argocd-rbac-cm.yaml
# PURPOSE: AUTHORIZATION: what each role can do and which group gets which role.
# CHANGE : Group emails and permissions.
# APPLY  : kubectl apply -f argocd-rbac-cm.yaml
# ======================================================================
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
  labels:
    app.kubernetes.io/name: argocd-rbac-cm
    app.kubernetes.io/part-of: argocd
data:
  policy.default: ""                    # no group = no access. Never use role:admin here
  scopes: "[groups]"                    # token claim holding the groups
  policy.csv: |
    # Format:  p, <role>, <resource>, <action>, <project>/<app>, <allow|deny>
    # ---- SRE: operate everything, change nothing structural ----
    p, role:sre, applications, get,      */*, allow
    p, role:sre, applications, sync,     */*, allow
    p, role:sre, applications, action/*, */*, allow
    p, role:sre, logs,         get,      */*, allow
    p, role:sre, projects,     get,      *,   allow
    p, role:sre, clusters,     get,      *,   allow
    p, role:sre, repositories, get,      *,   allow

    # ---- Junior DevOps: view all, act in staging only ----
    p, role:junior-devops, applications, get,      */*,       allow
    p, role:junior-devops, applications, sync,     staging/*, allow
    p, role:junior-devops, applications, action/*, staging/*, allow
    p, role:junior-devops, applications, delete,   */*,       deny
    p, role:junior-devops, logs,         get,      */*,       allow
    p, role:junior-devops, projects,     get,      *,         allow

    # ---- Developer: view all, deploy staging only ----
    p, role:developer, applications, get,  */*,       allow
    p, role:developer, applications, sync, staging/*, allow
    p, role:developer, logs,         get,  staging/*, allow
    p, role:developer, projects,     get,  *,         allow

    # ---- Group -> role bindings (Google groups arrive as emails) ----
    g, argocd-devops@example.com,        role:admin
    g, argocd-sre@example.com,           role:sre
    g, argocd-junior-devops@example.com, role:junior-devops
    g, argocd-developers@example.com,    role:developer
```

---

## Apply and Verify

```bash
kubectl -n argocd rollout restart deploy argocd-dex-server argocd-server
argocd login argocd.example.com --sso --grpc-web
argocd account get-user-info
argocd account can-i sync applications 'staging/myapp'
argocd account can-i sync applications 'prod/myapp'
argocd account can-i delete applications 'staging/myapp'
```

### Expected results
| Group | View prod | Sync staging | Sync prod | Delete app | Create app |
|---|---|---|---|---|---|
| devops (role:admin) | Yes | Yes | Yes | Yes | Yes |
| sre | Yes | Yes | Yes | No | No |
| junior-devops | Yes | Yes | No | No (explicit deny) | No |
| developer | Yes | Yes | No | No | No |
| in no group | login refused | No | No | No | No |

After one SSO admin login works, set `admin.enabled: "false"` and re-apply.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Login works, UI empty | Group string doesn't match a g, line | User Info, copy exact email, case matters |
| groups empty | Delegation scope/admin email/Admin SDK missing | Redo Google steps |
| Access denied at login | User in no allow-listed group | Add to group |
| redirect_uri_mismatch | Redirect differs | Exactly https://argocd.example.com/api/dex/callback |
| invalid_client | Wrong OAuth secret or missing part-of label | Check sso-secret.yaml |
| Dex: file not found | Key name or mount wrong | Key must be serviceaccount.json |
| Permission change no effect | Old token | Log out and in |

---

## Checklist

- [ ] policy.default empty
- [ ] Permissions attached to groups only
- [ ] Group membership managed only in Google
- [ ] 2+ people in DevOps group
- [ ] Local admin disabled after test
- [ ] Secrets encrypted in Git
- [ ] Service account has read-only groups scope only
