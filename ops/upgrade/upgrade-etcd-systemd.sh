#!/usr/bin/env bash
set -euo pipefail

TARGET_VERSION="${TARGET_VERSION:?set TARGET_VERSION, e.g. v3.5.17}"
ARCH="${ARCH:-amd64}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/etcd}"

sudo install -d "${BACKUP_DIR}"
etcdctl snapshot save "${BACKUP_DIR}/pre-upgrade-${TARGET_VERSION}-$(date +%Y%m%d%H%M%S).db"
etcdctl endpoint status --write-out=table

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT
curl -fsSL "https://github.com/etcd-io/etcd/releases/download/${TARGET_VERSION}/etcd-${TARGET_VERSION}-linux-${ARCH}.tar.gz" \
  -o "${tmpdir}/etcd.tgz"
tar -xzf "${tmpdir}/etcd.tgz" -C "${tmpdir}"

sudo systemctl stop etcd
sudo install -m 0755 "${tmpdir}/etcd-${TARGET_VERSION}-linux-${ARCH}/etcd" /usr/local/bin/etcd
sudo install -m 0755 "${tmpdir}/etcd-${TARGET_VERSION}-linux-${ARCH}/etcdctl" /usr/local/bin/etcdctl
sudo systemctl start etcd

etcd --version
etcdctl endpoint health
etcdctl endpoint status --write-out=table
