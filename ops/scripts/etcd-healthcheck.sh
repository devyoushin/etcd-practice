#!/usr/bin/env bash
set -euo pipefail

ENDPOINTS="${ENDPOINTS:-http://172.20.0.11:2379,http://172.20.0.12:2379,http://172.20.0.13:2379}"
CONTAINER="${CONTAINER:-etcd-1}"

docker exec "$CONTAINER" etcdctl \
  --endpoints="$ENDPOINTS" \
  endpoint health

docker exec "$CONTAINER" etcdctl \
  --endpoints="$ENDPOINTS" \
  endpoint status --write-out=table

docker exec "$CONTAINER" etcdctl \
  --endpoints="$ENDPOINTS" \
  member list --write-out=table
