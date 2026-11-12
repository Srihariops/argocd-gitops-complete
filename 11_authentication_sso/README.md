# 🔐 11 · Authentication (SSO & users)

> [!TIP]
> **Authentication = who are you?** (this folder). **Authorization = what may you do?** ([12_rbac](../12_rbac/README.md)). Choose ONE main login method, keep a break-glass admin until it works.

## 1. What & why
**Use case:** engineers log in with company Google/GitHub; leaving staff lose access automatically; CI uses robot tokens.

## 2. Architecture
```mermaid
flowchart LR
  U[User] --> UI[argocd-server]
  UI -->|via Dex| Dex[dex-server] --> G[Google Workspace] & GH[GitHub org] & LDAP[LDAP / SAML]
  UI -->|direct OIDC| OIDC[Keycloak · Okta · Azure AD · Google]
  UI --> Local[(local accounts<br/>admin · alice · ci-user)]
  UI --> RBAC[argocd-rbac-cm decides what the user may do]
```

## 3. Key values
| Key | Meaning | Example |
|---|---|---|
| `url` | External URL (SSO redirect base) | `https://argocd.example.com` |
| `dex.config` | Dex connectors (Google, GitHub, LDAP, SAML …) | see files |
| `oidc.config` | Direct OIDC provider (no Dex) | issuer + client |
| `redirectURI` / callback | Dex: `/api/dex/callback` · Direct OIDC: `/auth/callback` | exact match in provider |
| `hostedDomains` | Allowed Google domain(s) | `example.com` |
| `groups` (Google connector) | Allow-list of Workspace groups | emails |
| `admin.enabled` | Built-in admin | `"false"` after SSO |
| `accounts.<name>` | Local user capabilities | `apiKey, login` |

## 4. Choose your approach
| | A · Google + Dex (groups) | B · GitHub + Dex | C · Google direct OIDC | D · Keycloak/Okta/Azure OIDC | E · Local users |
|---|---|---|---|---|---|
| Group-based RBAC | ✅ Workspace groups | ✅ GitHub teams | ❌ email only | ✅ groups claim | n/a (user names) |
| Extra setup | service account + delegation | OAuth app | OAuth client only | provider client | none |
| Uses Dex | yes | yes | **no** | no | no |
| Best for | Google Workspace companies | GitHub-centric teams | small team, quick | enterprise IdP | CI robots, break-glass |

```mermaid
flowchart TD
  Q{What does your company use?} -->|Google Workspace| Q2{Need group-based access?}
  Q2 -->|yes| A[A · Google + Dex]
  Q2 -->|no, few people| C[C · Google direct OIDC]
  Q -->|GitHub org| B[B · GitHub + Dex]
  Q -->|Keycloak / Okta / Azure| D[D · OIDC with groups]
  Q -->|just CI bots| E[E · local users]
```

## 5. Approach A · Google + Dex (group based) — full steps
**Google one-time setup**
1. **Groups:** Admin Console → Directory → Groups: `argocd-devops@`, `argocd-sre@`, `argocd-junior-devops@`, `argocd-developers@`.
2. **OAuth client:** Cloud Console → APIs & Services → Credentials → OAuth client ID → *Web application*, redirect `https://argocd.example.com/api/dex/callback`.
3. **Service account:** enable *Admin SDK API*; create service account; create **JSON key**; note its numeric *Client ID*.
4. **Domain-wide delegation:** Admin Console → Security → API controls → *Add new*: that Client ID + scope `https://www.googleapis.com/auth/admin.directory.group.readonly`.
5. **Admin email:** a Workspace admin the service account impersonates (`domainToAdminEmail`).

```mermaid
sequenceDiagram
  participant U as User
  participant D as Dex
  participant G as Google
  U->>D: login
  D->>G: OAuth (email, profile)
  D->>G: Admin Directory API as service account: groups of this user?
  D-->>U: token with groups (emails)
```
<details>
<summary>📄 <b>google-oauth-secret.yaml</b> — OAuth client ID and secret (login button).</summary>

```yaml
# ======================================================================
# FILE   : google-oauth-secret.yaml
# PURPOSE: OAuth client ID and secret (login button).
# APPLY  : kubectl apply -f google-oauth-secret.yaml
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

</details>
<details>
<summary>📄 <b>google-sa-secret.yaml</b> — Service-account JSON key so Dex can read groups.</summary>

```yaml
# ======================================================================
# FILE   : google-sa-secret.yaml
# PURPOSE: Service-account JSON key so Dex can read groups.
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

</details>
<details>
<summary>📄 <b>google-dex-mount-patch.yaml</b> — Mount the key into the Dex pod.</summary>

```yaml
# ======================================================================
# FILE   : google-dex-mount-patch.yaml
# PURPOSE: Mount the key into the Dex pod.
# APPLY  : kubectl -n argocd patch deploy argocd-dex-server --patch-file google-dex-mount-patch.yaml
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

</details>
<details>
<summary>📄 <b>argocd-cm-google-dex.yaml</b> — Dex Google connector: domain, admin email, allowed groups.</summary>

```yaml
# ======================================================================
# FILE   : argocd-cm-google-dex.yaml
# PURPOSE: Dex Google connector: domain, admin email, allowed groups.
# APPLY  : kubectl apply -f argocd-cm-google-dex.yaml
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

</details>

> [!NOTE]
> With Helm, put `dex.config` under `configs.cm` and the volume under `dex.volumes` / `dex.volumeMounts` in values.yaml, otherwise Helm overwrites your edits.

## 6. Approach B · GitHub + Dex
<details>
<summary>📄 <b>github-oauth-secret.yaml</b> — GitHub OAuth app credentials.</summary>

```yaml
# ======================================================================
# FILE   : github-oauth-secret.yaml
# PURPOSE: GitHub OAuth app credentials.
# APPLY  : kubectl apply -f github-oauth-secret.yaml
# ======================================================================
apiVersion: v1
kind: Secret
metadata:
  name: argocd-sso-secret
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: argocd          # REQUIRED so Argo CD can read it with $argocd-sso-secret:key
type: Opaque
stringData:
  github.clientID: "<GITHUB_OAUTH_CLIENT_ID>"
  github.clientSecret: "<GITHUB_OAUTH_CLIENT_SECRET>"
```

</details>
<details>
<summary>📄 <b>argocd-cm-github-dex.yaml</b> — Dex GitHub connector: org, teams.</summary>

```yaml
# ======================================================================
# FILE   : argocd-cm-github-dex.yaml
# PURPOSE: Dex GitHub connector: org, teams.
# APPLY  : kubectl apply -f argocd-cm-github-dex.yaml
# ======================================================================
# GitHub login through Dex. Groups = GitHub TEAMS, written as  <org>:<team-slug>.
# 1) GitHub Org -> Settings -> Developer settings -> OAuth Apps -> New. Callback: https://argocd.example.com/api/dex/callback
# 2) Org -> Settings -> Third-party access: APPROVE the OAuth app (else teams are not visible)
# 3) Store clientID/secret (see github-oauth-secret.yaml) and restart dex + server
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
  labels: {app.kubernetes.io/name: argocd-cm, app.kubernetes.io/part-of: argocd}
data:
  url: https://argocd.example.com
  dex.config: |
    connectors:
      - type: github
        id: github
        name: GitHub                          # login button text
        config:
          clientID: $argocd-sso-secret:github.clientID
          clientSecret: $argocd-sso-secret:github.clientSecret
          orgs:
            - name: my-org                    # only members of this org can log in
              # teams: [devops, developers]   # optional: restrict to these teams only
          loadAllGroups: false                # true = return ALL teams of the user
          teamNameField: slug                 # group string = my-org:devops
          useLoginAsID: false
```

</details>

## 7. Approach C · Google direct OIDC (no Dex)
<details>
<summary>📄 <b>argocd-cm-oidc-google.yaml</b> — Built-in OIDC against Google; email-based RBAC.</summary>

```yaml
# ======================================================================
# FILE   : argocd-cm-oidc-google.yaml
# PURPOSE: Built-in OIDC against Google; email-based RBAC.
# APPLY  : kubectl apply -f argocd-cm-oidc-google.yaml
# ======================================================================
# GOOGLE WITHOUT DEX (simplest). Uses Argo CD's built-in OIDC.
# TRADE-OFF: Google tokens have NO group claim, so RBAC must use E-MAIL addresses (g, alice@example.com, role:x).
# Use Dex + service account (argocd-cm-google-dex.yaml) if you want Google GROUP based RBAC.
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
  labels: {app.kubernetes.io/name: argocd-cm, app.kubernetes.io/part-of: argocd}
data:
  url: https://argocd.example.com
  oidc.config: |
    name: Google
    issuer: https://accounts.google.com
    clientID: $argocd-sso-secret:google.clientID
    clientSecret: $argocd-sso-secret:google.clientSecret
    requestedScopes: [openid, profile, email]
    # Optional: only your domain (also set "Internal" user type on the Google OAuth consent screen)
    # requestedIDTokenClaims: {"hd": {"essential": true}}
# Redirect URI in Google Cloud: https://argocd.example.com/auth/callback   (note: /auth/callback, NOT /api/dex/callback)
# Disable Dex when not used:  Helm dex.enabled: false  /  kubectl -n argocd scale deploy argocd-dex-server --replicas=0
```

</details>

## 8. Approach D · Keycloak / Okta / Azure OIDC with groups
<details>
<summary>📄 <b>argocd-cm-oidc-groups.yaml</b> — Three provider examples with the groups claim.</summary>

```yaml
# ======================================================================
# FILE   : argocd-cm-oidc-groups.yaml
# PURPOSE: Three provider examples with the groups claim.
# APPLY  : kubectl apply -f argocd-cm-oidc-groups.yaml
# ======================================================================
# GENERIC OIDC WITH GROUPS: Keycloak, Okta, Azure AD (Entra ID), Auth0, AWS Cognito, GitLab ...
# Pick the example that matches your provider, delete the others.
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
  labels: {app.kubernetes.io/name: argocd-cm, app.kubernetes.io/part-of: argocd}
data:
  url: https://argocd.example.com
  oidc.config: |
    # ---------- Example 1: KEYCLOAK ----------
    name: Keycloak
    issuer: https://keycloak.example.com/realms/<realm>
    clientID: argocd
    clientSecret: $argocd-sso-secret:oidc.clientSecret
    requestedScopes: ["openid", "profile", "email", "groups"]      # create a "groups" client scope with a Group Membership mapper
    # Redirect URI in the provider: https://argocd.example.com/auth/callback

    # ---------- Example 2: OKTA ----------
    # name: Okta
    # issuer: https://<tenant>.okta.com
    # clientID: <client-id>
    # clientSecret: $argocd-sso-secret:oidc.clientSecret
    # requestedScopes: ["openid", "profile", "email", "groups"]    # add a "groups" claim to the authorization server

    # ---------- Example 3: AZURE AD / ENTRA ID ----------
    # name: Azure
    # issuer: https://login.microsoftonline.com/<TENANT_ID>/v2.0
    # clientID: <app-registration-client-id>
    # clientSecret: $argocd-sso-secret:oidc.clientSecret
    # requestedIDTokenClaims: {"groups": {"essential": true}}      # groups arrive as OBJECT IDs (GUIDs), use those in RBAC
    # requestedScopes: ["openid", "profile", "email"]
```

</details>
<details>
<summary>📄 <b>oidc-secret.yaml</b> — Client secret for OIDC providers.</summary>

```yaml
# ======================================================================
# FILE   : oidc-secret.yaml
# PURPOSE: Client secret for OIDC providers.
# APPLY  : kubectl apply -f oidc-secret.yaml
# ======================================================================
apiVersion: v1
kind: Secret
metadata:
  name: argocd-sso-secret
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: argocd
type: Opaque
stringData:
  oidc.clientSecret: "<CLIENT_SECRET_FROM_PROVIDER>"
```

</details>

## 9. Approach E · Local users and tokens
<details>
<summary>📄 <b>local-users-cm.yaml</b> — Human and robot accounts.</summary>

```yaml
# ======================================================================
# FILE   : local-users-cm.yaml
# PURPOSE: Human and robot accounts.
# APPLY  : kubectl apply -f local-users-cm.yaml
# ======================================================================
# LOCAL USERS: accounts stored in Argo CD itself. Good for robots (CI tokens) and tiny teams.
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
  labels: {app.kubernetes.io/name: argocd-cm, app.kubernetes.io/part-of: argocd}
data:
  accounts.alice: apiKey, login           # human: login (UI/CLI) + may create tokens
  accounts.bob: login                     # human: login only
  accounts.ci-user: apiKey                # robot: token only, cannot log in to the UI
  # accounts.alice.enabled: "false"       # disable (offboarding)
  admin.enabled: "true"                   # built-in admin; set "false" once SSO works
```

</details>
<details>
<summary>📄 <b>local-users-commands.sh</b> — Passwords, CI tokens, disable admin.</summary>

```bash
#!/bin/sh
# ======================================================================
# FILE   : local-users-commands.sh
# PURPOSE: Passwords, CI tokens, disable admin.
# APPLY  : run as needed
# ======================================================================
argocd account list
argocd account update-password --account alice --current-password '<admin-password>' --new-password '<strong>'   # admin sets it
argocd account generate-token --account ci-user                 # token for CI (store in Jenkins/GitHub secrets)
argocd account generate-token --account ci-user --expires-in 90d
argocd account delete-token --account ci-user <token-id>
# Give permissions in argocd-rbac-cm (folder 12):  g, alice, role:developer
# Disable admin after SSO:  kubectl -n argocd patch cm argocd-cm --type merge -p '{"data":{"admin.enabled":"false"}}'
```

</details>

## 10. Restart and test
<details>
<summary>📄 <b>restart-and-test.sh</b> — Restart Dex/server, read logs, check your groups.</summary>

```bash
#!/bin/sh
# ======================================================================
# FILE   : restart-and-test.sh
# PURPOSE: Restart Dex/server, read logs, check your groups.
# APPLY  : sh restart-and-test.sh
# ======================================================================
kubectl -n argocd rollout restart deploy argocd-dex-server argocd-server       # skip dex-server if Dex is not used
kubectl -n argocd logs deploy/argocd-dex-server --tail=50                      # login / group lookup errors
kubectl -n argocd logs deploy/argocd-server --tail=50                          # token / RBAC errors
argocd login argocd.example.com --sso --grpc-web
argocd account get-user-info                                                   # shows YOUR groups: copy them into RBAC
```

</details>

## 11. Troubleshooting
| Symptom | Cause | Fix |
|---|---|---|
| `redirect_uri_mismatch` | wrong callback | Dex: `/api/dex/callback`; direct OIDC: `/auth/callback` |
| Login OK, no groups | missing delegation / scope / admin email | redo Google steps 3-5 |
| `invalid_client` | wrong secret or Secret lacks `part-of: argocd` | check Secret label and key names |
| Access denied at login | user in no allow-listed group | add to a group in `groups:` |
| GitHub: no teams | OAuth app not approved by org | approve under third-party access |
| Dex: file not found | key name not `serviceaccount.json` | fix Secret key / mount |
| Works in UI, not CLI | gRPC through proxy | `--grpc-web` |

## 12. Checklist
- [ ] One main SSO method works · [ ] `admin.enabled: "false"` after test · [ ] ≥ 2 admins · [ ] secrets encrypted ([15](../15_secrets/README.md)) · [ ] users re-login after group changes
