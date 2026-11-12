#!/bin/sh
# ======================================================================
# FILE   : backup-restore.sh
# PURPOSE: Export/import and the GitOps rebuild plan.
# APPLY  : schedule daily
# ======================================================================
# BACKUP: everything Argo CD stores in the cluster (apps, projects, repos, settings). Run daily (CronJob / CI).
argocd admin export -n argocd > argocd-backup-$(date +%F).yaml        # contains secrets: encrypt it, store off-cluster (S3 + KMS)
# aws s3 cp argocd-backup-$(date +%F).yaml s3://<bucket>/argocd/ --sse aws:kms

# RESTORE (fresh Argo CD installed first)
argocd admin import -n argocd - < argocd-backup-2026-01-01.yaml

# REAL DR PLAN with GitOps: Applications/Projects are in Git, so:
#   1) install Argo CD (folder 02)  2) restore secrets (folder 15)  3) kubectl apply -f root-app.yaml  -> everything returns
