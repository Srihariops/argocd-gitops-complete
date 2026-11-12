#!/bin/sh
# ======================================================================
# FILE   : application-cli.sh
# PURPOSE: Create from Git, from a Helm repo, and edit.
# APPLY  : sh application-cli.sh
# ======================================================================
# Approach: create apps with the CLI
# Git folder (plain/kustomize/helm auto-detected)
argocd app create web-cli \
  --repo https://github.com/<org>/<gitops-repo>.git --revision main --path k8-manifest/web \
  --dest-server https://kubernetes.default.svc --dest-namespace web-dev \
  --project myargoproject-dev \
  --sync-policy automated --auto-prune --self-heal --sync-option CreateNamespace=true

# Helm chart repo
argocd app create nginx-cli --repo https://charts.bitnami.com/bitnami --helm-chart nginx --revision 18.2.0 \
  --dest-server https://kubernetes.default.svc --dest-namespace nginx-dev --project myargoproject-dev \
  --helm-set replicaCount=2

# Edit later
argocd app set web-cli --sync-policy none                 # switch to manual
argocd app set web-cli --kustomize-image nginx=nginx:1.27
argocd app get web-cli -o yaml > web-cli.yaml             # export as YAML to commit to Git
