# etcd 업그레이드 가이드

etcd 업그레이드는 데이터 저장소와 raft 클러스터 안정성에 직접 영향을 줍니다. 반드시 snapshot을 먼저 생성하고, 다중 노드 클러스터는 한 번에 한 멤버씩 순차 업그레이드합니다.

## 1. 사전 점검

```bash
export ETCDCTL_API=3
export TARGET_VERSION="v3.5.17"
export BACKUP_DIR="/var/backups/etcd"

etcdctl endpoint health
etcdctl endpoint status --write-out=table
etcdctl member list --write-out=table
```

Snapshot을 저장합니다.

```bash
sudo install -d ${BACKUP_DIR}
etcdctl snapshot save ${BACKUP_DIR}/pre-upgrade-${TARGET_VERSION}.db
etcdutl snapshot status ${BACKUP_DIR}/pre-upgrade-${TARGET_VERSION}.db --write-out=table
```

## 2. systemd 단일 노드 업그레이드

이 저장소의 실행 스크립트를 사용합니다.

```bash
TARGET_VERSION=${TARGET_VERSION} \
ARCH=amd64 \
BACKUP_DIR=${BACKUP_DIR} \
./ops/upgrade/upgrade-etcd-systemd.sh
```

직접 실행하려면 아래 흐름을 따릅니다.

```bash
curl -fsSL https://github.com/etcd-io/etcd/releases/download/${TARGET_VERSION}/etcd-${TARGET_VERSION}-linux-amd64.tar.gz \
  -o /tmp/etcd.tgz
tar -xzf /tmp/etcd.tgz -C /tmp

sudo systemctl stop etcd
sudo install -m 0755 /tmp/etcd-${TARGET_VERSION}-linux-amd64/etcd /usr/local/bin/etcd
sudo install -m 0755 /tmp/etcd-${TARGET_VERSION}-linux-amd64/etcdctl /usr/local/bin/etcdctl
sudo systemctl start etcd
```

## 3. 다중 노드 클러스터 업그레이드

각 멤버를 하나씩 업그레이드합니다. 한 멤버를 중지하기 전에 클러스터가 quorum을 유지할 수 있는지 확인합니다.

```bash
etcdctl endpoint status --cluster --write-out=table

# node-1에서만 수행
sudo systemctl stop etcd
# 바이너리 교체
sudo systemctl start etcd
etcdctl endpoint health --cluster

# node-1이 healthy가 된 뒤 node-2, node-3 순서로 반복
```

## 4. 확인

```bash
etcd --version
etcdctl endpoint health
etcdctl endpoint status --write-out=table
etcdctl member list --write-out=table
```

Kubernetes control plane의 etcd라면 kube-apiserver 로그와 API 응답도 함께 확인합니다.

## 5. 롤백

바이너리만 교체한 minor 업그레이드라면 이전 etcd 바이너리를 다시 설치하고 서비스를 재시작합니다.

```bash
sudo systemctl stop etcd
sudo install -m 0755 /path/to/old/etcd /usr/local/bin/etcd
sudo install -m 0755 /path/to/old/etcdctl /usr/local/bin/etcdctl
sudo systemctl start etcd
etcdctl endpoint health
```

데이터 호환성이 깨진 경우에는 서비스를 중지하고 업그레이드 전 snapshot으로 restore해야 합니다. restore는 기존 data-dir을 덮어쓰지 말고 새 data-dir에 복구한 뒤 systemd 설정을 전환합니다.

