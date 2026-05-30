#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/backups/etcd}"
CONTAINER="${CONTAINER:-etcd-1}"
ENDPOINTS="${ENDPOINTS:-http://172.20.0.11:2379}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
ETCD_IMAGE="${ETCD_IMAGE:-quay.io/coreos/etcd:v3.5.17}"

mkdir -p "$BACKUP_DIR"

SNAPSHOT_FILE="$BACKUP_DIR/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db"

docker exec "$CONTAINER" etcdctl \
  --endpoints="$ENDPOINTS" \
  snapshot save /tmp/snapshot.db

docker cp "$CONTAINER:/tmp/snapshot.db" "$SNAPSHOT_FILE"

docker run --rm \
  -v "$BACKUP_DIR:/backup" \
  "$ETCD_IMAGE" \
  etcdctl snapshot status "/backup/$(basename "$SNAPSHOT_FILE")" \
  --write-out=table

find "$BACKUP_DIR" -name "etcd-snapshot-*.db" -mtime +"$RETENTION_DAYS" -delete

echo "Backup completed: $SNAPSHOT_FILE"
