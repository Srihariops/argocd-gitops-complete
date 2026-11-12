#!/bin/sh
# ======================================================================
# FILE   : install-notifications.sh
# PURPOSE: Controller check and optional catalog install.
# APPLY  : sh install-notifications.sh
# ======================================================================
# Notifications controller ships with Argo CD (Helm: notifications.enabled: true; manifest: included).
kubectl -n argocd get deploy argocd-notifications-controller
# Optional: install the community CATALOG (ready-made triggers + templates, e.g. on-sync-failed, app-deployed)
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/notifications_catalog/install.yaml
# Helm users: set notifications.templates / notifications.triggers in values.yaml instead of editing the ConfigMap
