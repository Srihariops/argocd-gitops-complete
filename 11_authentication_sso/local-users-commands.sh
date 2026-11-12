#!/bin/sh
# ======================================================================
# FILE   : local-users-commands.sh
# PURPOSE: Passwords, CI tokens, disable admin.
# APPLY  : run as needed
# ======================================================================
argocd account list
argocd account update-password --account alice --current-password '<admin-password>' --new-password '<strong>'   # admin sets it
argocd account generate-token --account ci-user                 # token for CI (store in Jenkins/GitHub secrets)
argocd account generate-token --account ci-user --expires-in 90d
argocd account delete-token --account ci-user <token-id>
# Give permissions in argocd-rbac-cm (folder 12):  g, alice, role:developer
# Disable admin after SSO:  kubectl -n argocd patch cm argocd-cm --type merge -p '{"data":{"admin.enabled":"false"}}'
