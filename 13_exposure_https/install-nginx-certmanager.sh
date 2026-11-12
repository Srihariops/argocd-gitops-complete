#!/bin/sh
# ======================================================================
# FILE   : install-nginx-certmanager.sh
# PURPOSE: Install ingress-nginx, cert-manager, issuer, ingress.
# APPLY  : sh install-nginx-certmanager.sh
# ======================================================================
# Approach A prerequisites (EKS or any cluster)
helm upgrade --install ingress-nginx ingress-nginx --repo https://kubernetes.github.io/ingress-nginx -n ingress-nginx --create-namespace
helm repo add jetstack https://charts.jetstack.io && helm repo update
helm upgrade --install cert-manager jetstack/cert-manager -n cert-manager --create-namespace --set crds.enabled=true
kubectl -n cert-manager wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager --timeout=300s
kubectl apply -f clusterissuer-letsencrypt.yaml
kubectl apply -f ingress-nginx-certmanager.yaml
kubectl get svc -n ingress-nginx ingress-nginx-controller        # copy EXTERNAL-IP / hostname -> DNS CNAME/A record
kubectl get certificate -n argocd -w                              # READY True in 1-10 min
