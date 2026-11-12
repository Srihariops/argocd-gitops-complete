#!/bin/sh
# ======================================================================
# FILE   : rbac-ci-token.sh
# PURPOSE: JWT token for CI bound to a project role.
# APPLY  : sh rbac-ci-token.sh
# ======================================================================
# CI access with the LEAST privilege: a token bound to a project role (not an admin, not a human account).
argocd proj role create-token myargoproject-prod ci-bot --expires-in 90d     # prints a JWT
# In Jenkins / GitHub Actions:
#   export ARGOCD_SERVER=argocd.example.com
#   export ARGOCD_AUTH_TOKEN=<jwt>
#   argocd app sync fcoos-insights --grpc-web
argocd proj role list-tokens myargoproject-prod ci-bot
argocd proj role delete-token myargoproject-prod ci-bot <iat>                # revoke
# Alternative: local account token -> argocd account generate-token --account ci-user (folder 11)
