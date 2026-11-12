#!/bin/sh
# ======================================================================
# FILE   : docker-config-from-file.sh
# PURPOSE: Create a dockerconfigjson Secret from ~/.docker/config.json; credential-helper note.
# APPLY  : run the commands
# ======================================================================
# APPROACH E: build the registry Secret from your ~/.docker/config.json (".docker" approach). Good for ANY registry.
# 1) log in once (this writes ~/.docker/config.json)
aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com
#    Docker Hub:  docker login        GHCR: echo $PAT | docker login ghcr.io -u <user> --password-stdin

# 2) turn the file into a Kubernetes pull Secret (works for pods AND for Image Updater pullsecret:)
kubectl create secret generic ecr-pull-secret -n fcoos \
  --from-file=.dockerconfigjson=$HOME/.docker/config.json \
  --type=kubernetes.io/dockerconfigjson
kubectl create secret generic argocd-image-updater-secret -n argocd \
  --from-file=.dockerconfigjson=$HOME/.docker/config.json \
  --type=kubernetes.io/dockerconfigjson

# 3) WARNING: the ECR token inside expires in 12 h. For ECR prefer approach B or C. Static registries (Docker Hub, GHCR) are fine.
# Credential-helper alternative (no expiry handling by you): install docker-credential-ecr-login and set
#   { "credHelpers": { "<ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com": "ecr-login" } }  in config.json (needs IAM on the machine/pod)
