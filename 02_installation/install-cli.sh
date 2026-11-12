#!/bin/sh
# ======================================================================
# FILE   : install-cli.sh
# PURPOSE: Install the CLI and 5 ways to log in (port-forward, domain, SSO, token, core).
# APPLY  : sh install-cli.sh
# ======================================================================
# Approach D: install the argocd CLI (needed for any approach) and log in
# Linux
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd /usr/local/bin/argocd && rm argocd
# macOS:   brew install argocd
# Windows: choco install argocd-cli   (or download argocd-windows-amd64.exe)
argocd version --client

# ---- get first password ----
argocd admin initial-password -n argocd
#   same as: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d

# ---- login: pick ONE ----
# 1. Port-forward (no ingress yet)
kubectl -n argocd port-forward svc/argocd-server 8080:443 &
argocd login localhost:8080 --username admin --insecure
# 2. Through your domain (behind ingress/ALB)
# argocd login argocd.example.com --username admin --grpc-web
# 3. SSO
# argocd login argocd.example.com --sso --grpc-web
# 4. CI token (no interactive login)
# export ARGOCD_SERVER=argocd.example.com ARGOCD_AUTH_TOKEN=<token>; argocd app list --grpc-web
# 5. Core mode: talks to the cluster API directly, no Argo CD server needed
# kubectl config set-context --current --namespace=argocd; argocd login --core

argocd account update-password        # change the admin password
# after SSO works:  kubectl -n argocd delete secret argocd-initial-admin-secret
