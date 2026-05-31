#!/usr/bin/env bash
set -euo pipefail

ETCD_VERSION="${ETCD_VERSION:-v3.5.17}"
ARCH="${ARCH:-amd64}"
DOWNLOAD_URL="https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-${ARCH}.tar.gz"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

curl -fsSL "${DOWNLOAD_URL}" -o "${tmpdir}/etcd.tgz"
tar -xzf "${tmpdir}/etcd.tgz" -C "${tmpdir}"
sudo install -m 0755 "${tmpdir}/etcd-${ETCD_VERSION}-linux-${ARCH}/etcd" /usr/local/bin/etcd
sudo install -m 0755 "${tmpdir}/etcd-${ETCD_VERSION}-linux-${ARCH}/etcdctl" /usr/local/bin/etcdctl

sudo useradd --system --home /var/lib/etcd --shell /usr/sbin/nologin etcd 2>/dev/null || true
sudo install -d -o etcd -g etcd /var/lib/etcd

sudo tee /etc/systemd/system/etcd.service >/dev/null <<'SERVICE'
[Unit]
Description=etcd key-value store
After=network-online.target
Wants=network-online.target

[Service]
User=etcd
Type=notify
ExecStart=/usr/local/bin/etcd \
  --name=etcd-single \
  --data-dir=/var/lib/etcd \
  --listen-client-urls=http://0.0.0.0:2379 \
  --advertise-client-urls=http://127.0.0.1:2379 \
  --listen-peer-urls=http://0.0.0.0:2380 \
  --initial-advertise-peer-urls=http://127.0.0.1:2380 \
  --initial-cluster=etcd-single=http://127.0.0.1:2380 \
  --initial-cluster-state=new
Restart=always
RestartSec=5
LimitNOFILE=40000

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable --now etcd
etcdctl endpoint health
