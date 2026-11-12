#!/bin/sh
# ======================================================================
# FILE   : test-notifications.sh
# PURPOSE: Send a template now, run a trigger, read logs.
# APPLY  : sh test-notifications.sh
# ======================================================================
# Test without breaking anything
argocd admin notifications template notify app-deployed <app> --recipient slack:devops-alerts   # send a template now
argocd admin notifications trigger run on-sync-failed <app>                                      # evaluate a trigger
argocd admin notifications template get                                                          # list templates
kubectl -n argocd logs deploy/argocd-notifications-controller -f
