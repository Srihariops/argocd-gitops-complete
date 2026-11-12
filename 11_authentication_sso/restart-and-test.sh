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
