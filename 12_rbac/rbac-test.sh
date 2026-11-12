#!/bin/sh
# ======================================================================
# FILE   : rbac-test.sh
# PURPOSE: can-i, validate offline, simulate a role.
# APPLY  : sh rbac-test.sh
# ======================================================================
# TEST BEFORE YOU APPLY. 1) as the logged-in user
argocd account can-i sync applications 'myargoproject-dev/web'      # yes/no
argocd account can-i sync applications 'myargoproject-prod/web'
argocd account can-i delete applications 'myargoproject-dev/web'
argocd account get-user-info                                        # shows groups in YOUR token

# 2) offline, against a file or the live ConfigMap (no login needed)
kubectl -n argocd get cm argocd-rbac-cm -o jsonpath='{.data.policy\.csv}' > policy.csv
argocd admin settings rbac validate --policy-file policy.csv
argocd admin settings rbac can role:developer sync 'myargoproject-prod/web' --policy-file policy.csv
argocd admin settings rbac can argocd-sre@example.com sync 'myargoproject-prod/web' --policy-file policy.csv --default-role ''
