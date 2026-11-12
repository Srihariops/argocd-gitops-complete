# 02 · Installation

> ### 🟢 Simple version
> **In one line:** Put Argo CD into your cluster and open its web page.
> **Your goal:** Install, log in, change the admin password.
> **You will:** helm install → Open the UI → Install the CLI → Change password
> Need the full detail? Keep reading below. Otherwise jump to the files.


## Prerequisites
`kubectl`, `helm`, a cluster (EKS / kind / k3s), admin access.

## Method 1 (recommended): Helm
```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
kubectl create namespace argocd
helm install argocd argo/argo-cd -n argocd -f values.yaml     # values.yaml in this folder
kubectl -n argocd get pods                                     # wait for all Running
```
Upgrade later: `helm upgrade argocd argo/argo-cd -n argocd -f values.yaml`

## Method 2: plain manifest (quick lab)
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
# HA (production, 3 replicas):  .../manifests/ha/install.yaml
```

## Open the UI
```bash
# quick (temporary)
kubectl -n argocd port-forward svc/argocd-server 8080:443     # https://localhost:8080

# first admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```
For real use, expose with an Ingress + HTTPS: see [ingress.yaml](ingress.yaml).

## Install the CLI
```bash
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd /usr/local/bin/argocd && rm argocd
argocd version --client
argocd login argocd.example.com --username admin --grpc-web   # or: --sso
argocd account update-password                                # change password
```
After the password is changed and SSO works, delete the initial secret:
`kubectl -n argocd delete secret argocd-initial-admin-secret`

## Install flow
```mermaid
flowchart LR
  A[Create namespace] --> B[helm install] --> C[Pods Running] --> D[Ingress + TLS] --> E[CLI login] --> F[Change admin password] --> G[Setup SSO, disable admin]
```


---

## Files in this guide

| # | File | Purpose | What you change |
|---|---|---|---|
| 1 | [`values.yaml`](values.yaml) | Helm settings for Argo CD: URL, replicas, metrics, dex, notifications. | Your domain (global.domain, configs.cm.url). Keep admin.enabled true until SSO works. |
| 2 | [`ingress.yaml`](ingress.yaml) | Makes Argo CD reachable at https://argocd.example.com through an Ingress. | Host name, ingress class, TLS secret name, cert issuer. |

---

## The files, with explanations

Every file has `#` comments on each important line. Replace anything in `<angle brackets>`.

### File 1: `values.yaml`
**Purpose:** Helm settings for Argo CD: URL, replicas, metrics, dex, notifications.  
**What you change:** Your domain (global.domain, configs.cm.url). Keep admin.enabled true until SSO works.  
**Apply:** `helm install argocd argo/argo-cd -n argocd -f values.yaml`

```yaml
# ======================================================================
# FILE   : values.yaml
# PURPOSE: Helm settings for Argo CD: URL, replicas, metrics, dex, notifications.
# CHANGE : Your domain (global.domain, configs.cm.url). Keep admin.enabled true until SSO works.
# APPLY  : helm install argocd argo/argo-cd -n argocd -f values.yaml
# ======================================================================
# Helm values for Argo CD (production-leaning but simple).
# Use:  helm install argocd argo/argo-cd -n argocd -f values.yaml
global:
  domain: argocd.example.com          # your Argo CD URL (no https://)

configs:
  params:
    server.insecure: true             # TLS ends at the Ingress/ALB, so the server itself speaks plain HTTP
  cm:
    url: https://argocd.example.com   # external URL (needed for SSO)
    admin.enabled: "true"             # set "false" AFTER SSO works
    timeout.reconciliation: 180s      # how often Argo CD checks Git (default 3m)
    application.resourceTrackingMethod: annotation

controller:
  replicas: 1                         # keep 1 unless you shard many clusters
  metrics:
    enabled: true                     # Prometheus metrics (see 09_monitoring)
    serviceMonitor:
      enabled: false                  # set true if the Prometheus Operator is installed

server:
  replicas: 2                         # 2 = no downtime on restart
  metrics:
    enabled: true
    serviceMonitor:
      enabled: false

repoServer:
  replicas: 2
  metrics:
    enabled: true
    serviceMonitor:
      enabled: false

redis:
  enabled: true                       # for real HA use redis-ha instead

dex:
  enabled: true                       # needed for Google SSO (see 10_sso_rbac_google)

notifications:
  enabled: true                       # see 08_notifications

applicationSet:
  enabled: true                       # see 14_advanced
```

### File 2: `ingress.yaml`
**Purpose:** Makes Argo CD reachable at https://argocd.example.com through an Ingress.  
**What you change:** Host name, ingress class, TLS secret name, cert issuer.  
**Apply:** `kubectl apply -f ingress.yaml`

```yaml
# ======================================================================
# FILE   : ingress.yaml
# PURPOSE: Makes Argo CD reachable at https://argocd.example.com through an Ingress.
# CHANGE : Host name, ingress class, TLS secret name, cert issuer.
# APPLY  : kubectl apply -f ingress.yaml
# ======================================================================
# Expose Argo CD with an Ingress (nginx example). Needs: ingress-nginx + cert-manager.
# Works with server.insecure: true (see values.yaml).
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server
  namespace: argocd
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod      # auto TLS certificate
    nginx.ingress.kubernetes.io/ssl-redirect: "true"      # http -> https
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"  # server runs insecure behind the ingress
spec:
  ingressClassName: nginx
  rules:
    - host: argocd.example.com                            # your domain
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
  tls:
    - hosts:
        - argocd.example.com
      secretName: argocd-tls                              # cert-manager creates this
# AWS ALB users: use ingressClassName: alb + the alb.ingress.kubernetes.io/* annotations instead.
```

---

## Apply and Verify

```bash
kubectl -n argocd get pods            # all Running
kubectl -n argocd get ingress
argocd login argocd.example.com --grpc-web
argocd version
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Pods Pending | No node capacity | kubectl -n argocd describe pod <pod> |
| UI shows redirect loop | server.insecure not set behind TLS ingress | Set configs.params.server.insecure: true |
| CLI cannot connect | gRPC blocked by ingress | Use --grpc-web |

---

## Checklist

- [ ] All pods Running
- [ ] Admin password changed
- [ ] HTTPS works
- [ ] Initial admin secret deleted after SSO
- [ ] Replicas >= 2 for server and repo-server
