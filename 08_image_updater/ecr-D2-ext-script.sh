#!/bin/sh
# ======================================================================
# FILE   : ecr-D2-ext-script.sh
# PURPOSE: ext: script that prints AWS:token (needs aws-cli in the updater image).
# APPLY  : mount as /scripts/ecr-login.sh
# ======================================================================
# STYLE 2 helper: Image Updater runs this and reads "username:password" from stdout.
# Requires aws-cli in the Image Updater container (build a small custom image) and an IAM role on its ServiceAccount.
# Mount it via a ConfigMap at /scripts/ecr-login.sh (mode 0755) and set credentials: ext:/scripts/ecr-login.sh
echo "AWS:$(aws ecr get-login-password --region ap-south-1)"
