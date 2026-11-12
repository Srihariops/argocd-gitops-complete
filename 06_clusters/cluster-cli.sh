#!/bin/sh
# ======================================================================
# FILE   : cluster-cli.sh
# PURPOSE: Add, list, scope and remove clusters.
# APPLY  : sh cluster-cli.sh
# ======================================================================
# Approach A: CLI (easiest). Uses your kubeconfig context; creates a ServiceAccount + token in the target cluster.
kubectl config get-contexts -o name                      # find the context name
argocd cluster add <context-name> --name prod-eks        # add
argocd cluster add <context-name> --name prod-eks --project myargoproject-prod --yes      # scoped to one project
argocd cluster list                                      # confirm
argocd cluster get prod-eks
argocd cluster rm prod-eks                               # remove (apps must be moved first)
# EKS tip: aws eks update-kubeconfig --name <eks> --region ap-south-1 --alias prod-eks   (creates the context)
