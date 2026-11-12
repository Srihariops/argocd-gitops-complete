# 12 · Sample app (practice end to end)

> ### 🟢 Simple version
> **In one line:** A tiny ready app so you can practise without risk.
> **Your goal:** Copy it, deploy it, break it, roll it back.
> **You will:** Push to Git → Create app → Scale by hand and watch self-heal
> Need the full detail? Keep reading below. Otherwise jump to the files.


A tiny nginx app with Kustomize, in `k8-manifest/`. Use it to test projects, apps, sync, rollback and Image Updater.

```
k8-manifest/
├── kustomization.yaml    # lists files + image tag
├── namespace.yaml
├── deployment.yaml
├── service.yaml
└── hpa.yaml
```

## Try it
1. Copy `k8-manifest/` into your GitOps repo and push.
2. `kubectl apply -f ../03_projects/project-dev.yaml`
3. Edit `../04_applications/application.yaml` (repo URL, namespace `demo-dev`, path) and apply it.
4. Watch: `argocd app get demo` → Synced + Healthy.
5. Change `replicas` in Git → push → see it sync.
6. `kubectl scale deploy web -n demo-dev --replicas=5` → self-heal puts it back.
7. Break the image tag → Degraded → rollback with `git revert`.


---

## Files in this guide

| # | File | Purpose | What you change |
|---|---|---|---|
| 1 | [`k8-manifest/kustomization.yaml`](k8-manifest/kustomization.yaml) | Lists the files and image tag. | Tag. |
| 2 | [`k8-manifest/namespace.yaml`](k8-manifest/namespace.yaml) | Namespace created first (sync wave -1). | Name. |
| 3 | [`k8-manifest/deployment.yaml`](k8-manifest/deployment.yaml) | nginx Deployment with resources and probes. | Image/replicas. |
| 4 | [`k8-manifest/service.yaml`](k8-manifest/service.yaml) | Service for the Deployment. | Ports. |
| 5 | [`k8-manifest/hpa.yaml`](k8-manifest/hpa.yaml) | HorizontalPodAutoscaler 2 to 6 pods at 70% CPU. | Min/max/target. |

---

## The files, with explanations

Every file has `#` comments on each important line. Replace anything in `<angle brackets>`.

### File 1: `k8-manifest/kustomization.yaml`
**Purpose:** Lists the files and image tag.  
**What you change:** Tag.  
**Apply:** `(Argo CD builds this folder)`

```yaml
# ======================================================================
# FILE   : kustomization.yaml
# PURPOSE: Lists the files and image tag.
# CHANGE : Tag.
# APPLY  : (Argo CD builds this folder)
# ======================================================================
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: demo-dev          # applies to every resource below
resources:
  - namespace.yaml
  - deployment.yaml
  - service.yaml
  - hpa.yaml
images:
  - name: nginx
    newTag: "1.27"           # Image Updater / CI changes this line
```

### File 2: `k8-manifest/namespace.yaml`
**Purpose:** Namespace created first (sync wave -1).  
**What you change:** Name.  
**Apply:** `(synced by Argo CD)`

```yaml
# ======================================================================
# FILE   : namespace.yaml
# PURPOSE: Namespace created first (sync wave -1).
# CHANGE : Name.
# APPLY  : (synced by Argo CD)
# ======================================================================
apiVersion: v1
kind: Namespace
metadata:
  name: demo-dev
  annotations:
    argocd.argoproj.io/sync-wave: "-1"    # create first
```

### File 3: `k8-manifest/deployment.yaml`
**Purpose:** nginx Deployment with resources and probes.  
**What you change:** Image/replicas.  
**Apply:** `(synced by Argo CD)`

```yaml
# ======================================================================
# FILE   : deployment.yaml
# PURPOSE: nginx Deployment with resources and probes.
# CHANGE : Image/replicas.
# APPLY  : (synced by Argo CD)
# ======================================================================
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 2
  selector:
    matchLabels: {app: web}
  template:
    metadata:
      labels: {app: web}
    spec:
      containers:
        - name: web
          image: nginx                   # tag comes from kustomization.yaml
          ports: [{containerPort: 80}]
          resources:                     # ALWAYS set in production
            requests: {cpu: 50m, memory: 64Mi}
            limits: {cpu: 200m, memory: 128Mi}
          readinessProbe:                # Argo CD health depends on this
            httpGet: {path: /, port: 80}
            initialDelaySeconds: 3
          livenessProbe:
            httpGet: {path: /, port: 80}
            initialDelaySeconds: 10
```

### File 4: `k8-manifest/service.yaml`
**Purpose:** Service for the Deployment.  
**What you change:** Ports.  
**Apply:** `(synced by Argo CD)`

```yaml
# ======================================================================
# FILE   : service.yaml
# PURPOSE: Service for the Deployment.
# CHANGE : Ports.
# APPLY  : (synced by Argo CD)
# ======================================================================
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  selector: {app: web}
  ports: [{port: 80, targetPort: 80}]
```

### File 5: `k8-manifest/hpa.yaml`
**Purpose:** HorizontalPodAutoscaler 2 to 6 pods at 70% CPU.  
**What you change:** Min/max/target.  
**Apply:** `(synced by Argo CD)`

```yaml
# ======================================================================
# FILE   : hpa.yaml
# PURPOSE: HorizontalPodAutoscaler 2 to 6 pods at 70% CPU.
# CHANGE : Min/max/target.
# APPLY  : (synced by Argo CD)
# ======================================================================
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: web
spec:
  scaleTargetRef: {apiVersion: apps/v1, kind: Deployment, name: web}
  minReplicas: 2
  maxReplicas: 6
  metrics:
    - type: Resource
      resource: {name: cpu, target: {type: Utilization, averageUtilization: 70}}
# HPA changes replicas -> add ignoreDifferences for /spec/replicas in the Application.
```

---

## Apply and Verify

```bash
argocd app get demo
kubectl -n demo-dev get all
kubectl -n demo-dev scale deploy web --replicas=5   # self-heal puts it back to Git value
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| OutOfSync after HPA scales | replicas differ | Add ignoreDifferences /spec/replicas |

---

## Checklist

- [ ] Deployed, scaled by hand, self-healed
- [ ] Rolled back with git revert
