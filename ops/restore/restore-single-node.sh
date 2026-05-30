#!/usr/bin/env bash
set -euo pipefail

SNAPSHOT="${1:?Usage: restore-single-node.sh <snapshot.db>}"
RESTORE_DIR="${RESTORE_DIR:-/tmp/etcd-restore}"
ETCD_IMAGE="${ETCD_IMAGE:-quay.io/coreos/etcd:v3.5.17}"

rm -rf "$RESTORE_DIR"
mkdir -p "$RESTORE_DIR"

docker run --rm \
  -v "$(dirname "$SNAPSHOT"):/backup" \
  -v "$RESTORE_DIR:/restore" \
  "$ETCD_IMAGE" \
  etcdutl snapshot restore "/backup/$(basename "$SNAPSHOT")" \
    --name=etcd-single \
    --data-dir=/restore/etcd-single \
    --initial-advertise-peer-urls=http://127.0.0.1:2380 \
    --initial-cluster=etcd-single=http://127.0.0.1:2380 \
    --initial-cluster-token=etcd-single-token-restored \
    --initial-cluster-state=new

echo "Restored data directory: $RESTORE_DIR/etcd-single"
