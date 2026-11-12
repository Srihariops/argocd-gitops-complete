#!/bin/sh
# ======================================================================
# FILE   : commands-cheatsheet.sh
# PURPOSE: Most-used CLI and kubectl commands.
# ======================================================================
# Cheat sheet (read, do not run top to bottom)
# ---- login ----
argocd login argocd.example.com --sso --grpc-web
argocd account get-user-info
argocd account can-i sync applications 'myargoproject-dev/*'
# ---- look ----
argocd app list
argocd app get <app>                     # status, health, every resource
argocd app diff <app>                    # Git vs live
argocd app manifests <app>               # final rendered YAML
argocd app resources <app>
argocd app logs <app> --follow
argocd app history <app>                 # revisions (ID) for rollback
# ---- deploy ----
argocd app sync <app>
argocd app sync <app> --prune --force
argocd app sync <app> --resource apps:Deployment:<ns>/<name>      # one resource only
argocd app sync <app> --dry-run
argocd app wait <app> --health --timeout 300
argocd app get <app> --hard-refresh      # re-read Git, clear cache
# ---- change ----
argocd app set <app> --sync-policy none                    # manual
argocd app set <app> --sync-policy automated --auto-prune --self-heal
argocd app set <app> --revision <branch|tag|sha>
argocd app set <app> -p image.tag=008                      # Helm parameter override
# ---- operate pods (Argo CD resource actions) ----
argocd app actions list <app> --kind Deployment
argocd app actions run <app> restart --kind Deployment --resource-name web
# ---- stop / delete ----
argocd app terminate-op <app>
argocd app delete <app> --cascade        # also deletes deployed resources
# ---- rollback (see README for the right way) ----
argocd app rollback <app> <ID>
# ---- projects / repos / clusters ----
argocd proj list; argocd repo list; argocd cluster list
# ---- kubectl side ----
kubectl -n argocd get applications
kubectl -n argocd logs deploy/argocd-repo-server
kubectl -n argocd logs statefulset/argocd-application-controller
kubectl -n argocd patch app <app> --type merge -p '{"metadata":{"finalizers":null}}'   # unstick deletion
