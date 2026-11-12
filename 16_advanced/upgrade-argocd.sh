#!/bin/sh
# ======================================================================
# FILE   : upgrade-argocd.sh
# PURPOSE: Safe upgrade steps for Helm, manifest and GitOps installs.
# APPLY  : follow in order
# ======================================================================
# SAFE UPGRADE CHECKLIST (one minor version at a time)
# 1. Read release notes + "upgrading" guide:  https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/overview/
# 2. Backup:           argocd admin export -n argocd > backup-before-upgrade.yaml
# 3. Upgrade NON-prod first.
# 4. Helm:             helm upgrade argocd argo/argo-cd -n argocd --version <NEW_CHART> -f helm-values.yaml
#    Manifest:         kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/<NEW_VERSION>/manifests/install.yaml
#    Kustomize/GitOps: change <ARGOCD_VERSION> in Git, merge, sync the 'argocd' Application
# 5. Verify:           kubectl -n argocd get pods; argocd version; argocd app list   (all Synced?)
# 6. Re-test RBAC with `argocd account can-i` (permissions semantics change between majors)
# Rollback: helm rollback argocd <rev> -n argocd   (or re-apply the previous version URL)
