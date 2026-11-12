# 18 · Interview & real-time scenario questions

> ### 🟢 Simple version
> **In one line:** 25 questions and short answers to practise.
> **Your goal:** Read a few per day.
> **You will:** Basics first → Then scenarios
> Need the full detail? Keep reading below. Otherwise jump to the files.


Short answers you can say out loud. (Reference: chapter 14 of argocd-in-one-shot, extended with production scenarios.)

## Basics
**1. What is Argo CD?** A Kubernetes-native GitOps CD tool. It compares Git (desired) with the cluster (live) and syncs them.

**2. Push vs pull?** Push: CI runs `kubectl apply` and holds cluster credentials. Pull: Argo CD inside the cluster pulls from Git. Pull is safer and detects drift.

**3. Argo CD vs Jenkins?** Jenkins = CI (build/test/push image). Argo CD = CD (deploy from Git). Use both: Jenkins pushes the image, Argo CD deploys.

**4. Components?** server, repo-server, application-controller, dex, redis, notifications, applicationset controller.

**5. Synced vs Healthy?** Synced = cluster matches Git. Healthy = resources are actually working. An app can be Synced but Degraded.

**6. Self-heal vs prune?** Self-heal reverts manual cluster changes. Prune deletes resources removed from Git.

**7. Manual vs auto sync?** Auto for dev/staging; manual (or sync windows) for prod when you need a human gate.

**8. What are sync waves and hooks?** Waves order resources (lower first). Hooks run jobs at PreSync / PostSync / SyncFail (e.g. DB migration).

## Real-time scenarios
**9. A bad release is live. What do you do?** `git revert` the commit and push; Argo CD deploys the old version (Git stays the truth). In an emergency with auto-sync off: `argocd app rollback <app> <ID>`, then fix Git. If Image Updater is on, revert its commit too.

**10. App is OutOfSync forever.** Run `argocd app diff`. Usually a controller or HPA mutates a field → add `ignoreDifferences`. Or a defaulted field from a CRD/webhook.

**11. Someone ran `kubectl edit` in prod.** With selfHeal ON Argo CD reverts it within seconds. Without selfHeal it shows OutOfSync. Fix: change Git, not the cluster; restrict kubectl access.

**12. Sync stuck on "Running".** A hook or job is hanging: `argocd app terminate-op <app>`, check the hook pod and its delete policy.

**13. Application delete hangs.** Finalizer waiting for resources. Check what is stuck; as a last resort patch `metadata.finalizers` to null.

**14. Image pull fails with ECR.** ECR tokens last 12 h. Refresh pull secrets on a schedule (cron/CronJob) or use IRSA; confirm region/account match.

**15. How do you stop a developer deploying to prod?** Separate AppProjects, RBAC by SSO group (developers: sync staging only), prod sync window, branch protection and PR approval on the prod overlay.

**16. How do you manage secrets in GitOps?** Never plain in Git. Sealed Secrets, External Secrets Operator (AWS Secrets Manager) or SOPS.

**17. How do you promote dev → staging → prod?** Kustomize overlays per env. Dev tag auto-updated by Image Updater; staging/prod via reviewed PR that changes `newTag`.

**18. Image Updater: git vs argocd write-back?** `git` commits the tag to the repo (real GitOps, survives recreate). `argocd` only changes live state (testing).

**19. How do you handle many apps/clusters?** App-of-Apps for bootstrap, ApplicationSets (git/cluster generators) for scale, controller sharding for thousands of apps.

**20. How do you secure Argo CD itself?** HTTPS, SSO, disable local admin, `policy.default: ""`, least-privilege repo tokens, restricted projects, audit logs, network policies, regular upgrades.

**21. How do you back up / recover Argo CD?** Everything is in Git: reinstall Argo CD and apply the root app. Also `argocd admin export` and back up secrets/encryption keys.

**22. Canary vs blue/green?** Canary shifts traffic gradually and watches metrics. Blue/green runs both versions and switches all traffic at once (instant rollback, double pods).

**23. Argo CD says "Unknown" for all apps.** Check repo-server and controller logs, repo credentials, cluster connectivity, Redis health.

**24. Config change not applied.** Argo CD polls Git every 3 min. Use a webhook or `argocd app get <app> --hard-refresh`.

**25. UI login works but shows nothing.** Group in token doesn't match any `g,` line in `argocd-rbac-cm`. Check User Info, copy the exact group string, log out and in.
