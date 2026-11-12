#!/bin/sh
# ======================================================================
# FILE   : install-monitoring.sh
# PURPOSE: kube-prometheus-stack and Grafana access.
# APPLY  : sh install-monitoring.sh
# ======================================================================
# kube-prometheus-stack = Prometheus + Alertmanager + Grafana + Operator (CRDs: ServiceMonitor, PrometheusRule)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
kubectl -n monitoring get pods
# Grafana (default admin / prom-operator: CHANGE IT)
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
# Dashboards -> Import -> ID 14584 (Argo CD) -> choose Prometheus
