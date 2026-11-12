#!/bin/bash
# ======================================================================
# FILE   : sealed-secret-howto.sh
# PURPOSE: Commands to install and use Sealed Secrets.
# CHANGE : Secret names and values (locally only).
# APPLY  : run the commands step by step
# ======================================================================
# HOW TO USE SEALED SECRETS (commands, run them one by one; this is a guide, not a script to run blindly)
# 1) Install the controller in the cluster
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets sealed-secrets/sealed-secrets -n kube-system

# 2) Install the kubeseal CLI on your laptop (see https://github.com/bitnami-labs/sealed-secrets/releases)

# 3) Make a normal Secret file locally (DO NOT commit it) ...
kubectl create secret generic repo-gitops -n argocd \
  --from-literal=username=<user> --from-literal=password=<token> \
  --dry-run=client -o yaml > /tmp/secret.yaml

# 4) ... encrypt it. The output is SAFE to commit to Git
kubeseal --format yaml < /tmp/secret.yaml > sealed-repo-gitops.yaml
rm /tmp/secret.yaml

# 5) Commit sealed-repo-gitops.yaml. The controller creates the real Secret in the cluster.
# IMPORTANT: back up the controller key, otherwise you cannot decrypt after a rebuild:
kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > sealed-secrets-key-BACKUP.yaml   # store offline!
