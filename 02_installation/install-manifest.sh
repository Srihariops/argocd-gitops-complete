#!/bin/sh
# ======================================================================
# FILE   : install-manifest.sh
# PURPOSE: kubectl install in 4 flavours (server-side apply).
# APPLY  : sh install-manifest.sh
# ======================================================================
# Approach B: plain manifest with kubectl
kubectl create namespace argocd

# B1. Standard (single replicas) - use server-side apply because CRDs are big
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/<ARGOCD_VERSION>/manifests/install.yaml

# B2. HA (3 replicas, redis-ha) - production
# kubectl apply -n argocd --server-side --force-conflicts \
#   -f https://raw.githubusercontent.com/argoproj/argo-cd/<ARGOCD_VERSION>/manifests/ha/install.yaml

# B3. Core (no UI/API/Dex; only controllers, for CLI --core use)
# kubectl apply -n argocd --server-side --force-conflicts \
#   -f https://raw.githubusercontent.com/argoproj/argo-cd/<ARGOCD_VERSION>/manifests/core-install.yaml

# B4. Namespace-scoped (no cluster-wide permissions; multi-tenant)
# kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/<ARGOCD_VERSION>/manifests/namespace-install.yaml

kubectl -n argocd get pods -w
