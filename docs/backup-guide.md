# 백업 및 복원

etcd는 **스냅샷(Snapshot)** 으로 데이터를 백업합니다. 정기적인 스냅샷은 재해 복구의 핵심입니다.

---

## 스냅샷 개념

```
etcd 데이터
  │
  ├── WAL (Write-Ahead Log) — 순서대로 기록된 변경 로그
  └── Snapshot — 특정 시점의 전체 상태 스냅샷 (BoltDB 파일)

백업 = Snapshot 파일 저장
복원 = Snapshot으로 새 데이터 디렉토리 초기화
```

> **중요**: Follower나 Leader 모두에서 스냅샷을 찍을 수 있지만,
> **Follower에서 찍는 것을 권장**합니다 (Leader 부하 감소).

---

## 스냅샷 백업

```bash
# 단일 노드 스냅샷
docker exec etcd etcdctl \
  --endpoints=http://172.20.0.11:2379 \
  snapshot save /tmp/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db

# 스냅샷을 호스트로 복사
docker cp etcd:/tmp/etcd-snapshot-20260405-120000.db ./backups/

# 스냅샷 파일 검증
docker run --rm \
  -v $(pwd)/backups:/backup \
  quay.io/coreos/etcd:v3.5.17 \
  etcdctl snapshot status /backup/etcd-snapshot-20260405-120000.db \
  --write-out=table
```

스냅샷 상태 출력 예시:
```
+----------+----------+------------+------------+
|   HASH   | REVISION | TOTAL KEYS | TOTAL SIZE |
+----------+----------+------------+------------+
| 7a9b2c3d |     1234 |        567 |      2.3MB |
+----------+----------+------------+------------+
```

---

## 정기 백업 스크립트

```bash
#!/bin/bash
# backup-etcd.sh

BACKUP_DIR="/backups/etcd"
CONTAINER="etcd-1"
ENDPOINTS="http://172.20.0.11:2379"
RETENTION_DAYS=7

# 백업 디렉토리 생성
mkdir -p $BACKUP_DIR

# 스냅샷 파일명
SNAPSHOT_FILE="$BACKUP_DIR/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db"

# 스냅샷 생성
docker exec $CONTAINER etcdctl \
  --endpoints=$ENDPOINTS \
  snapshot save /tmp/snapshot.db

# 호스트로 복사
docker cp $CONTAINER:/tmp/snapshot.db $SNAPSHOT_FILE

# 검증
docker run --rm \
  -v $BACKUP_DIR:/backup \
  quay.io/coreos/etcd:v3.5.17 \
  etcdctl snapshot status /backup/$(basename $SNAPSHOT_FILE) \
  --write-out=table

if [ $? -eq 0 ]; then
  echo "$(date): 백업 성공 → $SNAPSHOT_FILE"
else
  echo "$(date): 백업 검증 실패!" >&2
  exit 1
fi

# 오래된 백업 삭제 (7일 이상)
find $BACKUP_DIR -name "etcd-snapshot-*.db" -mtime +$RETENTION_DAYS -delete
echo "$(date): ${RETENTION_DAYS}일 이상 된 백업 삭제 완료"
```

```bash
# 스크립트 권한 설정
chmod +x backup-etcd.sh

# 크론으로 매일 새벽 3시 실행
crontab -e
# 0 3 * * * /path/to/backup-etcd.sh >> /var/log/etcd-backup.log 2>&1
```

---

## 스냅샷 복원

복원은 **클러스터를 완전히 새로 초기화**합니다.

### 1. 단일 노드 복원

```bash
# 1. 기존 컨테이너 중지
docker stop etcd
docker rm etcd
docker volume rm etcd-data

# 2. 스냅샷으로 데이터 복원
docker run --rm \
  -v $(pwd)/backups:/backup \
  -v etcd-data:/etcd-data \
  quay.io/coreos/etcd:v3.5.17 \
  etcdctl snapshot restore /backup/etcd-snapshot-20260405-120000.db \
    --name=etcd-single \
    --data-dir=/etcd-data \
    --initial-cluster=etcd-single=http://0.0.0.0:2380 \
    --initial-cluster-token=etcd-single-token \
    --initial-advertise-peer-urls=http://0.0.0.0:2380

# 3. 복원된 데이터로 컨테이너 시작
docker run -d \
  --name etcd \
  -p 2379:2379 \
  -v etcd-data:/etcd-data \
  quay.io/coreos/etcd:v3.5.17 \
  etcd \
  --name=etcd-single \
  --data-dir=/etcd-data \
  --advertise-client-urls=http://0.0.0.0:2379 \
  --listen-client-urls=http://0.0.0.0:2379 \
  --initial-advertise-peer-urls=http://0.0.0.0:2380 \
  --listen-peer-urls=http://0.0.0.0:2380 \
  --initial-cluster=etcd-single=http://0.0.0.0:2380 \
  --initial-cluster-state=new \
  --initial-cluster-token=etcd-single-token

# 4. 데이터 복원 확인
docker exec etcd etcdctl get "" --prefix --keys-only
```

---

### 2. 3중화 클러스터 복원

```bash
# 1. 모든 노드 중지 및 데이터 삭제
docker compose -f compose-3node.yaml down -v

# 2. 각 노드 데이터 복원 (동일 스냅샷 사용)
# etcd-1
docker run --rm \
  -v $(pwd)/backups:/backup \
  -v etcd1-data:/etcd-data \
  quay.io/coreos/etcd:v3.5.17 \
  etcdctl snapshot restore /backup/etcd-snapshot-20260405-120000.db \
    --name=etcd-1 \
    --data-dir=/etcd-data \
    --initial-cluster=etcd-1=http://172.20.0.11:2380,etcd-2=http://172.20.0.12:2380,etcd-3=http://172.20.0.13:2380 \
    --initial-cluster-token=etcd-cluster-token-restored \
    --initial-advertise-peer-urls=http://172.20.0.11:2380

# etcd-2
docker run --rm \
  -v $(pwd)/backups:/backup \
  -v etcd2-data:/etcd-data \
  quay.io/coreos/etcd:v3.5.17 \
  etcdctl snapshot restore /backup/etcd-snapshot-20260405-120000.db \
    --name=etcd-2 \
    --data-dir=/etcd-data \
    --initial-cluster=etcd-1=http://172.20.0.11:2380,etcd-2=http://172.20.0.12:2380,etcd-3=http://172.20.0.13:2380 \
    --initial-cluster-token=etcd-cluster-token-restored \
    --initial-advertise-peer-urls=http://172.20.0.12:2380

# etcd-3
docker run --rm \
  -v $(pwd)/backups:/backup \
  -v etcd3-data:/etcd-data \
  quay.io/coreos/etcd:v3.5.17 \
  etcdctl snapshot restore /backup/etcd-snapshot-20260405-120000.db \
    --name=etcd-3 \
    --data-dir=/etcd-data \
    --initial-cluster=etcd-1=http://172.20.0.11:2380,etcd-2=http://172.20.0.12:2380,etcd-3=http://172.20.0.13:2380 \
    --initial-cluster-token=etcd-cluster-token-restored \
    --initial-advertise-peer-urls=http://172.20.0.13:2380

# 3. 복원된 데이터로 클러스터 시작
# compose 파일에서 --initial-cluster-token을 복원 시 사용한 값으로 변경 후
docker compose -f compose-3node.yaml up -d

# 4. 복원 확인
ENDPOINTS="http://172.20.0.11:2379,http://172.20.0.12:2379,http://172.20.0.13:2379"
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS \
  endpoint status --write-out=table

docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS \
  get "" --prefix --keys-only
```

> **토큰 변경**: 복원 시 `--initial-cluster-token`을 이전과 **다른 값**으로 설정하는 것을 권장합니다.
> 같은 네트워크에서 이전 클러스터 멤버와 혼동을 방지합니다.

---

## 정리 (Defrag)

스냅샷 후 빈 공간을 정리하여 DB 파일 크기를 줄입니다.

```bash
ENDPOINTS="http://172.20.0.11:2379,http://172.20.0.12:2379,http://172.20.0.13:2379"

# 현재 DB 크기 확인
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS \
  endpoint status --write-out=json | \
  jq '.[] | {endpoint: .Endpoint, dbSize: (.Status.dbSize | . / 1024 / 1024 | floor | tostring + " MB")}'

# Defrag (Follower 먼저, Leader 마지막)
# 한 번에 1개씩 실행 (클러스터 부하 감소)
docker exec etcd-1 etcdctl defrag --endpoints=http://172.20.0.12:2379
docker exec etcd-1 etcdctl defrag --endpoints=http://172.20.0.13:2379
docker exec etcd-1 etcdctl defrag --endpoints=http://172.20.0.11:2379  # Leader

# Defrag 후 크기 재확인
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS \
  endpoint status --write-out=json | \
  jq '.[] | {endpoint: .Endpoint, dbSize: (.Status.dbSize | . / 1024 / 1024 | floor | tostring + " MB")}'
```

---

## 참고 링크

- [etcd 백업 공식 문서](https://etcd.io/docs/v3.5/op-guide/recovery/)
- [etcdctl snapshot](https://etcd.io/docs/v3.5/dev-guide/interacting_v3/#snapshot)
- [etcd 운영 모범 사례](https://etcd.io/docs/v3.5/op-guide/maintenance/)
