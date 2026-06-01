#!/usr/bin/env bash
set -euo pipefail

ETCD_NAMESPACE="${ETCD_NAMESPACE:-etcd}"
RELEASE="${RELEASE:-etcd}"

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update bitnami

kubectl create namespace "${ETCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install "${RELEASE}" bitnami/etcd \
  --namespace "${ETCD_NAMESPACE}" \
  --set replicaCount=3 \
  --wait \
  --timeout 10m

kubectl get pods -n "${ETCD_NAMESPACE}"
