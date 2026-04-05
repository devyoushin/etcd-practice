# 고가용성 운영

---

## 멤버 교체 (Rolling Update)

클러스터 운영 중 노드를 교체해야 할 때의 절차입니다.
**항상 한 번에 1개씩** 교체하여 쿼럼을 유지해야 합니다.

```
3중화 기준:
  ✓ 1개 교체 중 → 2/3 정상 → 쿼럼 유지 (안전)
  ✗ 2개 동시 교체 → 1/3 정상 → 쿼럼 붕괴 (위험)
```

---

### 안전한 멤버 교체 절차

```bash
ENDPOINTS="http://172.20.0.11:2379,http://172.20.0.12:2379,http://172.20.0.13:2379"

# 1. 현재 멤버 목록 확인
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS \
  member list --write-out=table

# 2. 교체할 멤버의 ID 확인 (예: etcd-3)
MEMBER_ID=$(docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS \
  member list --write-out=json | \
  jq -r '.members[] | select(.name=="etcd-3") | .ID')
echo "etcd-3 멤버 ID: $MEMBER_ID"

# 3. 멤버 제거
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS \
  member remove $MEMBER_ID

# 클러스터 상태 확인 (2개 멤버만 남음, 쿼럼 유지)
docker exec etcd-1 etcdctl \
  --endpoints=http://172.20.0.11:2379,http://172.20.0.12:2379 \
  endpoint status --write-out=table

# 4. 기존 데이터 디렉토리 삭제 (필수!)
docker stop etcd-3
docker rm etcd-3
docker volume rm etcd3-data  # 이전 데이터 완전 삭제

# 5. 새 멤버를 클러스터에 추가
docker exec etcd-1 etcdctl \
  --endpoints=http://172.20.0.11:2379,http://172.20.0.12:2379 \
  member add etcd-3 --peer-urls=http://172.20.0.13:2380

# 6. 새 컨테이너 시작 (--initial-cluster-state=existing 주의!)
docker run -d \
  --name etcd-3 \
  --network etcd-practice_etcd-net \
  --ip 172.20.0.13 \
  -v etcd3-data:/etcd-data \
  quay.io/coreos/etcd:v3.5.17 \
  etcd \
  --name=etcd-3 \
  --data-dir=/etcd-data \
  --listen-client-urls=http://0.0.0.0:2379 \
  --advertise-client-urls=http://172.20.0.13:2379 \
  --listen-peer-urls=http://0.0.0.0:2380 \
  --initial-advertise-peer-urls=http://172.20.0.13:2380 \
  --initial-cluster=etcd-1=http://172.20.0.11:2380,etcd-2=http://172.20.0.12:2380,etcd-3=http://172.20.0.13:2380 \
  --initial-cluster-state=existing \  # ← new가 아닌 existing!
  --initial-cluster-token=etcd-cluster-token

# 7. 데이터 동기화 완료 확인
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS \
  member list --write-out=table
# etcd-3가 started 상태로 돌아오면 성공
```

> **핵심**: 기존 클러스터에 노드를 추가할 때는 반드시
> `--initial-cluster-state=existing`을 사용합니다.
> `new`를 사용하면 클러스터가 분리됩니다(Split-brain).

---

## Leader 강제 이전 (Leader Transfer)

유지보수 시 현재 Leader를 다른 노드로 이전합니다.

```bash
ENDPOINTS="http://172.20.0.11:2379,http://172.20.0.12:2379,http://172.20.0.13:2379"

# 현재 Leader 확인
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS \
  endpoint status --write-out=table

# Leader 강제 이전 (모든 엔드포인트에서 가장 최신 Follower로)
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS \
  move-leader

# 새 Leader 확인
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS \
  endpoint status --write-out=table
```

---

## 쿼럼 손실 후 복구 (재해 복구)

클러스터의 과반수 노드가 영구적으로 손실된 경우입니다.
이 경우 **스냅샷으로 새 클러스터를 재구성**해야 합니다.

> **경고**: 이 절차는 클러스터를 완전히 재구성합니다.
> 마지막 스냅샷 이후의 데이터는 유실될 수 있습니다.

```bash
# 1. 살아남은 노드에서 스냅샷 저장
docker exec etcd-1 etcdctl \
  --endpoints=http://172.20.0.11:2379 \
  snapshot save /tmp/recovery-snapshot.db

# 스냅샷을 호스트로 복사
docker cp etcd-1:/tmp/recovery-snapshot.db ./recovery-snapshot.db

# 2. 스냅샷 검증
docker run --rm \
  -v $(pwd):/backup \
  quay.io/coreos/etcd:v3.5.17 \
  etcdctl snapshot status /backup/recovery-snapshot.db --write-out=table

# 3. 기존 클러스터 전체 중지 및 삭제
docker compose -f compose-3node.yaml down -v

# 4. 스냅샷으로 각 노드 데이터 복원
for i in 1 2 3; do
  docker run --rm \
    -v $(pwd):/backup \
    -v etcd${i}-data:/etcd-data \
    quay.io/coreos/etcd:v3.5.17 \
    etcdctl snapshot restore /backup/recovery-snapshot.db \
      --name=etcd-${i} \
      --data-dir=/etcd-data \
      --initial-cluster=etcd-1=http://172.20.0.11:2380,etcd-2=http://172.20.0.12:2380,etcd-3=http://172.20.0.13:2380 \
      --initial-cluster-token=etcd-cluster-token-new \
      --initial-advertise-peer-urls=http://172.20.0.1${i}:2380
done

# 5. 복원된 데이터로 클러스터 재시작
# compose 파일에서 --initial-cluster-state=new 확인 후 시작
docker compose -f compose-3node.yaml up -d

# 6. 데이터 복원 확인
docker exec etcd-1 etcdctl endpoint status --write-out=table
```

---

## 클러스터 확장 (3중화 → 5중화)

운영 중인 3중화 클러스터에 노드를 추가합니다.

```bash
ENDPOINTS_3="http://172.20.0.11:2379,http://172.20.0.12:2379,http://172.20.0.13:2379"

# 1. etcd-4 추가
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS_3 \
  member add etcd-4 --peer-urls=http://172.20.0.14:2380

# 반환된 환경 변수 확인 (ETCD_INITIAL_CLUSTER 등)

# 2. etcd-4 컨테이너 시작 (existing 상태로)
docker run -d \
  --name etcd-4 \
  --network etcd-practice_etcd-net \
  --ip 172.20.0.14 \
  -v etcd4-data:/etcd-data \
  quay.io/coreos/etcd:v3.5.17 \
  etcd \
  --name=etcd-4 \
  --data-dir=/etcd-data \
  --listen-client-urls=http://0.0.0.0:2379 \
  --advertise-client-urls=http://172.20.0.14:2379 \
  --listen-peer-urls=http://0.0.0.0:2380 \
  --initial-advertise-peer-urls=http://172.20.0.14:2380 \
  --initial-cluster=etcd-1=http://172.20.0.11:2380,etcd-2=http://172.20.0.12:2380,etcd-3=http://172.20.0.13:2380,etcd-4=http://172.20.0.14:2380 \
  --initial-cluster-state=existing \
  --initial-cluster-token=etcd-cluster-token

# 3. etcd-4 데이터 동기화 완료 대기
sleep 10
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS_3,http://172.20.0.14:2379 \
  member list --write-out=table

# 4. etcd-5 추가 (동일 절차)
ENDPOINTS_4="$ENDPOINTS_3,http://172.20.0.14:2379"
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS_4 \
  member add etcd-5 --peer-urls=http://172.20.0.15:2380

docker run -d \
  --name etcd-5 \
  --network etcd-practice_etcd-net \
  --ip 172.20.0.15 \
  -v etcd5-data:/etcd-data \
  quay.io/coreos/etcd:v3.5.17 \
  etcd \
  --name=etcd-5 \
  --data-dir=/etcd-data \
  --listen-client-urls=http://0.0.0.0:2379 \
  --advertise-client-urls=http://172.20.0.15:2379 \
  --listen-peer-urls=http://0.0.0.0:2380 \
  --initial-advertise-peer-urls=http://172.20.0.15:2380 \
  --initial-cluster=etcd-1=http://172.20.0.11:2380,etcd-2=http://172.20.0.12:2380,etcd-3=http://172.20.0.13:2380,etcd-4=http://172.20.0.14:2380,etcd-5=http://172.20.0.15:2380 \
  --initial-cluster-state=existing \
  --initial-cluster-token=etcd-cluster-token

# 5. 최종 확인
ENDPOINTS_5="$ENDPOINTS_4,http://172.20.0.15:2379"
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS_5 \
  endpoint status --write-out=table
```

---

## HA 상태 점검 체크리스트

```bash
ENDPOINTS="http://172.20.0.11:2379,http://172.20.0.12:2379,http://172.20.0.13:2379"

# 1. 모든 노드 헬스 체크
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS \
  endpoint health

# 2. 각 노드 상태 및 Leader 확인
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS \
  endpoint status --write-out=table

# 3. 멤버 목록 (모두 started 상태여야 함)
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS \
  member list --write-out=table

# 4. DB 크기 및 Revision 확인
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS \
  endpoint status --write-out=json | \
  jq '.[] | {endpoint: .Endpoint, dbSize: .Status.dbSize, revision: .Status.header.revision}'

# 5. 알람 확인
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS \
  alarm list
```

---

## 운영 시 주의사항

| 상황 | 권장 행동 |
|---|---|
| 노드 1개 재시작 | 자동 복구, 특별한 조치 불필요 |
| 노드 교체 | 반드시 1개씩, `existing` 상태로 추가 |
| 데이터 디렉토리 분실 | 멤버 제거 후 `existing`으로 재추가 |
| 쿼럼 손실 | 스냅샷으로 새 클러스터 재구성 |
| DB 크기 급증 | `etcdctl compact` + `etcdctl defrag` |
| `NOSPACE` 알람 | 즉시 컴팩션, 디스크 공간 확보 |

```bash
# NOSPACE 알람 해제 (컴팩션 후)
REVISION=$(docker exec etcd-1 etcdctl endpoint status --write-out=json | \
  jq '.[0].Status.header.revision')
docker exec etcd-1 etcdctl compact $REVISION
docker exec etcd-1 etcdctl defrag --endpoints=$ENDPOINTS
docker exec etcd-1 etcdctl alarm disarm
```

---

## 참고 링크

- [etcd 멤버 관리](https://etcd.io/docs/v3.5/op-guide/runtime-configuration/)
- [etcd 재해 복구](https://etcd.io/docs/v3.5/op-guide/recovery/)
- [etcd 클러스터 확장](https://etcd.io/docs/v3.5/op-guide/runtime-reconf-design/)
