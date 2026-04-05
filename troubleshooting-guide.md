# 트러블슈팅 가이드

---

## 진단 명령어 모음

```bash
ENDPOINTS="http://172.20.0.11:2379,http://172.20.0.12:2379,http://172.20.0.13:2379"

# 전체 헬스 체크
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS \
  endpoint health

# 각 노드 상태 (Leader, DB 크기, Revision)
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS \
  endpoint status --write-out=table

# 멤버 목록
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS \
  member list --write-out=table

# 알람 목록
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS \
  alarm list

# 컨테이너 로그 확인
docker logs etcd-1 --tail=100
docker logs etcd-1 -f   # follow

# etcd 이벤트 실시간 확인
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS \
  watch "" --prefix --rev=0
```

---

## 자주 발생하는 문제

### 클러스터가 시작되지 않음

```bash
# 증상: etcd 컨테이너가 계속 재시작됨
docker ps -a  # Restarting 상태 확인
docker logs etcd-1 | tail -30
```

**원인별 해결:**

| 로그 메시지 | 원인 | 해결 방법 |
|---|---|---|
| `no such file or directory` | 데이터 디렉토리 없음 | 볼륨 마운트 확인 |
| `conflict with existing cluster` | `--initial-cluster-state` 오류 | 기존 클러스터면 `existing`, 신규면 `new` |
| `member already exists in cluster` | 중복 멤버 추가 시도 | 기존 멤버 제거 후 재추가 |
| `raft: tocommit(X) is out of range` | 데이터 디렉토리 손상 | 새 데이터 디렉토리로 멤버 재추가 |
| `request timed out` | 쿼럼 미달 | 정상 노드 수 확인 |

---

### Leader 없음 (No Leader)

```bash
# 증상
etcdserver: request timed out, possibly due to lost leader

# 확인
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS \
  endpoint status --write-out=json | jq '.[] | {ep: .Endpoint, leader: .Status.leader}'
# leader 값이 0이면 해당 노드는 Leader를 모름

# 원인 1: 과반수 노드 다운 → 쿼럼 손실
docker ps -a  # 실행 중인 etcd 컨테이너 수 확인

# 해결: 다운된 노드 재시작
docker start etcd-2 etcd-3

# 원인 2: 네트워크 파티션 → 노드들이 서로 통신 불가
# 컨테이너 네트워크 확인
docker network inspect etcd-practice_etcd-net
docker exec etcd-1 ping 172.20.0.12
```

---

### 특정 노드가 클러스터에서 이탈 (unstarted/unresponsive)

```bash
# 멤버 상태 확인
docker exec etcd-1 etcdctl member list --write-out=table
# STATUS가 unstarted 또는 응답 없음

# 원인: 네트워크 장애, 데이터 손상, OOM

# 해결: 해당 멤버 제거 후 재추가
MEMBER_ID=<이탈한 멤버 ID>
docker exec etcd-1 etcdctl \
  --endpoints=http://172.20.0.11:2379,http://172.20.0.12:2379 \
  member remove $MEMBER_ID

# 데이터 디렉토리 삭제 후 existing 상태로 재추가
# (ha-guide.md의 멤버 교체 절차 참고)
```

---

### NOSPACE 알람 (DB 용량 부족)

```bash
# 알람 확인
docker exec etcd-1 etcdctl alarm list
# NOSPACE 알람이 있으면 쓰기 거부됨

# 해결 절차:
# 1. 현재 Revision 확인
REVISION=$(docker exec etcd-1 etcdctl \
  --endpoints=http://172.20.0.11:2379 \
  endpoint status --write-out=json | jq '.[0].Status.header.revision')
echo "현재 Revision: $REVISION"

# 2. 컴팩션 (이전 Revision 데이터 삭제)
docker exec etcd-1 etcdctl \
  --endpoints=http://172.20.0.11:2379 \
  compact $REVISION

# 3. Defrag (각 노드)
docker exec etcd-1 etcdctl defrag --endpoints=http://172.20.0.12:2379
docker exec etcd-1 etcdctl defrag --endpoints=http://172.20.0.13:2379
docker exec etcd-1 etcdctl defrag --endpoints=http://172.20.0.11:2379

# 4. 알람 해제
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS \
  alarm disarm

# 5. 알람 해제 확인
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS \
  alarm list   # 빈 응답이면 정상
```

---

### etcd DB 크기가 계속 증가

```bash
# DB 크기 확인
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS \
  endpoint status --write-out=json | \
  jq '.[] | {ep: .Endpoint, dbSizeMB: (.Status.dbSize / 1024 / 1024 | floor)}'

# 원인: 자동 컴팩션 미설정
# 해결: etcd 시작 시 아래 플래그 추가
# --auto-compaction-mode=revision
# --auto-compaction-retention=1000  # 최근 1000 Revision만 유지
# 또는
# --auto-compaction-mode=periodic
# --auto-compaction-retention=1h    # 1시간 이전 데이터 자동 삭제

# 수동 컴팩션 + defrag
REVISION=$(docker exec etcd-1 etcdctl \
  --endpoints=http://172.20.0.11:2379 \
  endpoint status --write-out=json | jq '.[0].Status.header.revision')

docker exec etcd-1 etcdctl compact $REVISION
docker exec etcd-1 etcdctl defrag --endpoints=$ENDPOINTS
```

---

### 쓰기 지연 (High Write Latency)

```bash
# 원인 진단
docker logs etcd-1 | grep -i "slow" | tail -20
docker logs etcd-1 | grep -i "took too long" | tail -20
# "apply entries took too long" → 디스크 I/O 문제
# "leader failed to send heartbeat" → 네트워크 지연

# 디스크 성능 확인
docker run --rm \
  -v etcd1-data:/etcd-data \
  busybox dd if=/dev/zero of=/etcd-data/test bs=4k count=10000 && \
  docker run --rm -v etcd1-data:/etcd-data busybox rm /etcd-data/test

# etcd 데이터는 SSD에 저장하는 것을 강권
# HDD 사용 시 --heartbeat-interval=200 --election-timeout=2000 으로 타임아웃 완화
```

---

### Watch 이벤트 누락

```bash
# 원인: 컴팩션으로 인해 이전 Revision 데이터 삭제
# 에러 메시지: "rpc error: code = OutOfRange, required revision has been compacted"

# 해결: Watch 시 현재 Revision부터 시작
CURRENT_REV=$(docker exec etcd-1 etcdctl \
  --endpoints=http://172.20.0.11:2379 \
  endpoint status --write-out=json | jq '.[0].Status.header.revision')

docker exec etcd-1 etcdctl \
  --endpoints=http://172.20.0.11:2379 \
  watch /mykey --rev=$CURRENT_REV
```

---

### 초기 클러스터 구성 실패 (피어 간 통신 불가)

```bash
# 로그 확인
docker logs etcd-1 | grep -i "peer\|dial\|connect" | tail -20

# 컨테이너 IP 확인
docker inspect etcd-1 | jq '.[0].NetworkSettings.Networks'
docker inspect etcd-2 | jq '.[0].NetworkSettings.Networks'

# 피어 포트(2380) 통신 확인
docker exec etcd-1 nc -zv 172.20.0.12 2380

# --initial-cluster 주소가 실제 컨테이너 IP와 일치하는지 확인
docker exec etcd-1 cat /proc/1/cmdline | tr '\0' ' '
```

---

## 로그 레벨 조정

```bash
# 상세 로그 활성화 (디버그)
docker exec etcd-1 etcdctl \
  --endpoints=http://172.20.0.11:2379 \
  --command-timeout=5s \
  member list

# etcd 시작 시 로그 레벨 설정
# --log-level=debug  (debug, info, warn, error, panic, fatal)
# --logger=zap       (zap 권장)
```

---

## 참고 링크

- [etcd 트러블슈팅 공식 문서](https://etcd.io/docs/v3.5/op-guide/failures/)
- [etcd 알람 관리](https://etcd.io/docs/v3.5/op-guide/maintenance/#space-quota)
- [etcd 성능 튜닝](https://etcd.io/docs/v3.5/op-guide/performance/)
