# 🎤 20 · Interview & Real-time Scenario Q&A

> [!TIP]
> Short answers you can say out loud, grouped from basics to production scenarios.

## Basics
**1. What is Argo CD?** A Kubernetes-native GitOps CD tool: it compares Git (desired) with the cluster (live) and syncs them.

**2. Push vs pull deployment?** Push: CI runs `kubectl apply` and holds cluster credentials. Pull: Argo CD inside the cluster pulls from Git. Pull is safer and detects drift.

**3. Argo CD vs Jenkins?** Jenkins = CI (build, test, push image). Argo CD = CD (deploy from Git). Use both.

**4. Components?** server, repo-server, application-controller, dex, redis, applicationset-controller, notifications.

**5. Synced vs Healthy?** Synced = live equals Git. Healthy = resources work. An app can be Synced but Degraded.

**6. Self-heal vs prune?** Self-heal reverts manual edits. Prune deletes resources removed from Git.

**7. Ways to install Argo CD?** Helm (customisable), plain manifest (quick/HA/core), Kustomize (GitOps, self-managed). Always pin the version.

**8. Ways to create an Application?** UI, CLI, YAML (production), ApplicationSet (fleets).

**9. Sync waves and hooks?** Waves order resources (lower first). Hooks run jobs at PreSync/PostSync/SyncFail, for example DB migrations.

## Production scenarios
**10. Bad release is live. What now?** `git revert` and push (Git stays true). Emergency with auto-sync: turn it off, `argocd app rollback`, fix Git, turn it on. Also revert Image Updater's commit.

**11. App OutOfSync forever?** `argocd app diff`; usually HPA or a webhook mutates a field → `ignoreDifferences`.

**12. Someone ran `kubectl edit` in prod?** selfHeal reverts it; otherwise it shows OutOfSync. Fix Git, restrict kubectl.

**13. Sync stuck on Running?** A hook/job hangs: `argocd app terminate-op`.

**14. Delete hangs?** Finalizer waits for resources; check what is stuck, last resort patch finalizers.

**15. Image Updater: git vs argocd write-back?** `git` commits the tag (real GitOps, survives recreate, easy revert). `argocd` only overrides live state (testing).

**16. How do you handle ECR token expiry?** ECR passwords last 12 h. Best: CronJob with an IAM role (IRSA), no static keys. Alternatives: CronJob/cron with access keys, `registries.conf` credentials, `.docker/config.json` for static registries. On EKS pods can pull via the node IAM role.

**17. Update strategies?** semver (releases), newest-build (Jenkins numbers), digest (mutable tag), alphabetical (date tags).

**18. Google SSO with groups?** Dex + service account with domain-wide delegation reads Workspace groups. Without Dex (direct OIDC) there are no groups, so RBAC uses e-mails.

**19. GitHub SSO?** Dex GitHub connector; groups are `org:team`; the OAuth app must be approved by the org.

**20. Global RBAC vs project roles?** Global (`argocd-rbac-cm`) for org-wide roles; project roles for per-project rules and CI tokens owned by the team.

**21. How do you stop developers deploying to prod?** Separate projects, RBAC by group (developers sync dev only), prod manual/sync window, PR approval on the prod overlay.

**22. Secrets in GitOps?** Never plain: Sealed Secrets, External Secrets (AWS Secrets Manager), SOPS, or Vault plugin.

**23. Promote dev → prod?** Kustomize overlays or Helm values per env; dev by Image Updater, staging/prod by approved PR changing one tag.

**24. Many apps/clusters?** App-of-Apps for bootstrap, ApplicationSet generators, controller sharding, webhooks.

**25. Canary vs blue/green?** Canary shifts traffic gradually and can auto-abort on metrics. Blue/green runs both and switches at once (instant rollback, double pods).

**26. How to expose Argo CD with HTTPS?** NGINX + cert-manager (any cluster), ALB + ACM (EKS), passthrough, or LoadBalancer. If TLS ends earlier set `server.insecure: true`; CLI with `--grpc-web`.

**27. Backup and DR?** Everything is in Git: reinstall Argo CD, restore secrets, apply the root app. Also `argocd admin export`.

**28. Config change not applied?** Git polling is 3 min: use a webhook or `--hard-refresh`.

**29. UI login works but shows nothing?** Group in token ≠ `g,` line. Check User Info, exact text, re-login.

**30. How do you secure Argo CD itself?** HTTPS, SSO, disable local admin, `policy.default: ""`, read-only repo credentials, restricted projects, `exec.enabled: false`, network policies, regular upgrades.
