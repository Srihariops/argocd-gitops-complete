#!/bin/sh
# ======================================================================
# FILE   : install-helm.sh
# PURPOSE: Commands: add repo, install, upgrade, uninstall.
# APPLY  : sh install-helm.sh
# ======================================================================
# Approach A: Helm
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm search repo argo/argo-cd --versions | head -5             # choose a chart version
kubectl create namespace argocd
helm install argocd argo/argo-cd -n argocd --version <CHART_VERSION> -f helm-values.yaml
# upgrade:   helm upgrade argocd argo/argo-cd -n argocd --version <NEW_VERSION> -f helm-values.yaml
# uninstall: helm uninstall argocd -n argocd        (CRDs stay; delete them manually if needed)
