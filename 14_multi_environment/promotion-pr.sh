#!/bin/sh
# ======================================================================
# FILE   : promotion-pr.sh
# PURPOSE: Change one line, open a PR, approve, sync.
# APPLY  : sh promotion-pr.sh
# ======================================================================
# PROMOTION = a pull request that changes ONE line (the image tag) in the next environment.
# dev is updated by Image Updater (folder 08). Staging/prod are promoted by humans or a pipeline:
git checkout -b promote-prod-007
sed -i 's/newTag: ".*"/newTag: "007"/' k8-manifest/web/overlays/prod/kustomization.yaml     # Helm: edit envs/prod.yaml image.tag
git commit -am "promote web 007 to prod" && git push -u origin promote-prod-007
gh pr create --title "Promote web 007 to prod" --body "Verified in staging" --base main        # review + approval -> merge -> Sync prod
