#!/bin/bash
# ======================================================================
# FILE   : ecr-A2-host-cron-refresh.sh
# PURPOSE: Script for crontab: new token into two docker-registry secrets.
# APPLY  : crontab: 0 */6 * * * /bin/bash <path>
# ======================================================================
# Refreshes ECR login tokens (they expire every 12h) into Kubernetes docker-registry Secrets.
# Run from cron every 6h (see bottom). Needs: kubectl, aws cli.
set -Eeuo pipefail

# ---------------- CONFIG: edit these ----------------
AWS_NAMESPACE="argocd"                 # where the AWS key secret lives
AWS_SECRET="aws-ecr-credentials"       # secret with AWS_ACCESS_KEY_ID etc. (secrets.yaml, Secret A)
ECR_REGISTRY="<ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com"   # MUST match region/account of your images

ARGO_NAMESPACE="argocd"                # Image Updater reads this secret
ARGO_SECRET="argocd-image-updater-secret"
APP_NAMESPACE="fcoos"                  # app namespace; pods use this as imagePullSecret
APP_SECRET="ecr-pull-secret"
# -----------------------------------------------------

for cmd in kubectl aws base64; do
  command -v "$cmd" >/dev/null || { echo "ERROR: $cmd not found"; exit 1; }
done

get() { kubectl get secret "$AWS_SECRET" -n "$AWS_NAMESPACE" -o jsonpath="{.data.$1}" | base64 -d; }
export AWS_ACCESS_KEY_ID="$(get AWS_ACCESS_KEY_ID)"
export AWS_SECRET_ACCESS_KEY="$(get AWS_SECRET_ACCESS_KEY)"
export AWS_DEFAULT_REGION="$(get AWS_DEFAULT_REGION)"

[[ -n "$AWS_ACCESS_KEY_ID" && -n "$AWS_SECRET_ACCESS_KEY" && -n "$AWS_DEFAULT_REGION" ]] || { echo "ERROR: AWS values missing"; exit 1; }
trap 'unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION ECR_TOKEN' EXIT

aws sts get-caller-identity >/dev/null && echo "AWS auth OK (region $AWS_DEFAULT_REGION)"
ECR_TOKEN="$(aws ecr get-login-password --region "$AWS_DEFAULT_REGION")"

update_ecr_secret() {                  # $1=namespace  $2=secret name
  kubectl create secret docker-registry "$2" -n "$1" \
    --docker-server="$ECR_REGISTRY" --docker-username=AWS --docker-password="$ECR_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "Updated: $1/$2"
}
update_ecr_secret "$ARGO_NAMESPACE" "$ARGO_SECRET"   # for Image Updater
update_ecr_secret "$APP_NAMESPACE"  "$APP_SECRET"    # for pods pulling images
echo "Done at $(date)"

# ---------------- SETUP ----------------
# mkdir -p ~/awsecr && chmod 700 ~/awsecr/refresh-ecr-secrets.sh
# bash ~/awsecr/refresh-ecr-secrets.sh                      # test once
# crontab -e   ->  0 */6 * * * /bin/bash ~/awsecr/refresh-ecr-secrets.sh >> ~/awsecr/refresh.log 2>&1
# Your Deployments must list:  imagePullSecrets: [{name: ecr-pull-secret}]
