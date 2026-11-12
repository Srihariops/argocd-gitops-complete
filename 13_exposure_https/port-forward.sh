#!/bin/sh
# ======================================================================
# FILE   : port-forward.sh
# PURPOSE: Private access without exposure.
# APPLY  : sh port-forward.sh
# ======================================================================
# APPROACH E: no exposure at all (private access for admins / first install)
kubectl -n argocd port-forward svc/argocd-server 8080:443        # UI: https://localhost:8080  (accept the self-signed cert)
argocd login localhost:8080 --username admin --insecure
# or without port-forward: argocd login --core      (talks to the Kubernetes API, no Argo CD server needed)
