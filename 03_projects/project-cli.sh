#!/bin/sh
# ======================================================================
# FILE   : project-cli.sh
# PURPOSE: Create a project, windows, roles and tokens with the CLI.
# APPLY  : sh project-cli.sh
# ======================================================================
# Approach B: create and tune a project with the CLI (good for quick tests; use YAML for production)
argocd proj create myargoproject-dev -d https://kubernetes.default.svc,'*-dev' -s https://github.com/<org>/<gitops-repo>.git
argocd proj add-source myargoproject-dev https://github.com/<org>/another-repo.git
argocd proj add-destination myargoproject-dev https://kubernetes.default.svc 'extra-dev'
argocd proj allow-cluster-resource myargoproject-dev "" Namespace      # allow Namespace creation
argocd proj windows add myargoproject-prod --kind deny --schedule "0 9 * * 1-5" --duration 8h --applications '*' --manual-sync
argocd proj role create myargoproject-prod deployer
argocd proj role add-policy myargoproject-prod deployer --action sync --permission allow --object '*'
argocd proj role create-token myargoproject-prod deployer           # JWT for CI (see folder 12)
argocd proj list && argocd proj get myargoproject-prod
