#!/bin/sh
# ======================================================================
# FILE   : repo-cli.sh
# PURPOSE: argocd repo add for every type.
# APPLY  : sh repo-cli.sh
# ======================================================================
# Approach: CLI (stores the same Secret for you)
argocd repo add https://github.com/<org>/<repo>.git --username <user> --password <token> --project myargoproject-dev   # HTTPS
argocd repo add git@github.com:<org>/<repo>.git --ssh-private-key-path ~/.ssh/argocd-deploy-key                       # SSH
argocd repo add https://charts.example.com --type helm --name company-charts --username u --password p                 # Helm repo
argocd repo add <acct>.dkr.ecr.ap-south-1.amazonaws.com --type helm --name ecr-charts --enable-oci --username AWS --password "$(aws ecr get-login-password --region ap-south-1)"
argocd repocreds add https://github.com/<org> --username <user> --password <token>                                    # template for a whole org
argocd repo list        # Status must be Successful
# Test the same token outside Argo CD:  git ls-remote https://<user>:<token>@github.com/<org>/<repo>.git
