# 대규모 온프레미스 k8s 환경 — etcd 이슈 대응 가이드

etcd는 Kubernetes 클러스터의 핵심 데이터 저장소입니다. etcd 장애는 곧 클러스터 전체 정지를 의미하므로, 대규모 온프레미스 환경에서는 **예방 → 관측 → 신속 대응 → 복구** 의 4단계 체계가 필수입니다.

---

## 목차

1. [사전 예방 (Proactive Design)](#1-사전-예방-proactive-design)
2. [관측 가능성 (Observability)](#2-관측-가능성-observability)
3. [1차 진단 (First Response)](#3-1차-진단-first-response)
4. [시나리오별 대응](#4-시나리오별-대응)
5. [대규모 k8s 특화 고려사항](#5-대규모-k8s-특화-고려사항)
6. [백업 및 복구 전략](#6-백업-및-복구-전략)
7. [정기 점검 체크리스트](#7-정기-점검-체크리스트)
8. [인시던트 심각도 분류 및 Runbook](#8-인시던트-심각도-분류-및-runbook)

---

## 1. 사전 예방 (Proactive Design)

### 1-1. 클러스터 설계 원칙

| 항목 | 권장 | 금지 |
|---|---|---|
| 노드 수 | 5 (대규모), 3 (소규모) | 짝수 노드 |
| etcd 전용 서버 | control plane과 물리 서버 분리 | kube-apiserver와 동일 서버 혼용 |
| 스토리지 | NVMe SSD (전용 디스크) | HDD, NFS, 공유 볼륨 |
| 네트워크 | etcd 전용 NIC (피어/클라이언트 분리) | 데이터 플레인 네트워크 공유 |
| OS | 전용 튜닝 적용 (아래 참고) | 범용 설정 그대로 사용 |

### 1-2. etcd 시작 플래그 (대규모 클러스터 권장값)

```bash
etcd \
  # 데이터
  --data-dir=/var/lib/etcd \
  --wal-dir=/var/lib/etcd-wal \           # WAL 전용 디스크 분리 권장

  # 쿼럼 / 타이밍
  --heartbeat-interval=100 \              # 기본값 (SSD 환경)
  --election-timeout=1000 \              # heartbeat의 10배
  # HDD 환경이라면: --heartbeat-interval=200, --election-timeout=2000

  # 용량
  --quota-backend-bytes=8589934592 \     # 8GB (기본 2GB → 대규모 부족)
  --max-request-bytes=1572864 \          # 1.5MB (큰 Secret/ConfigMap 대비)

  # 자동 컴팩션
  --auto-compaction-mode=periodic \
  --auto-compaction-retention=8h \       # 8시간 이전 revision 자동 삭제

  # 스냅샷
  --snapshot-count=10000 \               # 10000 변경마다 스냅샷 (기본값)

  # 로그
  --logger=zap \
  --log-level=info \

  # TLS (프로덕션 필수)
  --cert-file=/etc/etcd/pki/server.crt \
  --key-file=/etc/etcd/pki/server.key \
  --trusted-ca-file=/etc/etcd/pki/ca.crt \
  --client-cert-auth=true \
  --peer-cert-file=/etc/etcd/pki/peer.crt \
  --peer-key-file=/etc/etcd/pki/peer.key \
  --peer-trusted-ca-file=/etc/etcd/pki/ca.crt \
  --peer-client-cert-auth=true
```

### 1-3. OS 수준 튜닝

```bash
# 파일 디스크립터 한도 증가
ulimit -n 65536
echo "etcd soft nofile 65536" >> /etc/security/limits.conf
echo "etcd hard nofile 65536" >> /etc/security/limits.conf

# etcd 프로세스 I/O 우선순위 상향 (실시간 클래스)
ionice -c 1 -n 0 -p $(pgrep etcd)

# 스왑 비활성화 (메모리 지연 방지)
swapoff -a
sed -i '/swap/d' /etc/fstab

# 디스크 스케줄러를 none(noop)으로 변경 (NVMe/SSD)
echo none > /sys/block/nvme0n1/queue/scheduler

# vm.dirty_ratio 조정 (etcd 데이터 디렉토리 마운트 기준)
echo 10 > /proc/sys/vm/dirty_ratio
echo 5  > /proc/sys/vm/dirty_background_ratio
```

### 1-4. 디스크 성능 사전 검증 (fio 벤치마크)

etcd는 fsync 지연에 극도로 민감합니다. **배포 전 반드시 측정**하세요.

```bash
# etcd 데이터 디렉토리에서 순차 쓰기 + fsync 지연 측정
fio --rw=write --ioengine=sync --fdatasync=1 \
    --directory=/var/lib/etcd \
    --size=22m --bs=2300 \
    --name=etcd-disk-test \
    --output-format=json | \
    jq '.jobs[0].sync.lat_ns | {p50: .percentile."50.000000", p99: .percentile."99.000000"}' | \
    awk '{print $0, "ns"}'

# 목표: p99 fsync < 10ms (10,000,000 ns)
# 10ms 초과 시: NVMe 교체 또는 heartbeat-interval/election-timeout 완화 필요
```

---

## 2. 관측 가능성 (Observability)

### 2-1. 핵심 Prometheus 메트릭 및 알람 임계값

etcd는 기본적으로 `:2381/metrics` 엔드포인트에서 Prometheus 메트릭을 노출합니다.

| 메트릭 | 알람 조건 | 의미 |
|---|---|---|
| `etcd_server_leader_changes_seen_total` | 1시간 내 rate > 3 | 리더 불안정 (디스크/네트워크 문제) |
| `etcd_disk_wal_fsync_duration_seconds` (p99) | > 10ms | WAL 쓰기 지연 → 리더 선출 불안 |
| `etcd_disk_backend_commit_duration_seconds` (p99) | > 25ms | BoltDB 커밋 지연 → 쓰기 성능 저하 |
| `etcd_mvcc_db_total_size_in_bytes` | quota의 75% 이상 | NOSPACE 알람 임박 |
| `etcd_server_proposals_failed_total` | 증가 추세 | 쿼럼 또는 네트워크 문제 |
| `etcd_network_peer_round_trip_time_seconds` (p99) | > 150ms | 피어 간 네트워크 지연 |
| `etcd_server_has_leader` | == 0 | 리더 없음 → 클러스터 쓰기 불가 |
| `etcd_server_is_learner` | — | Learner 멤버 존재 여부 확인 |
| `process_resident_memory_bytes` | > 시스템 RAM의 40% | 메모리 압박 (OOM 위험) |

### 2-2. 권장 Prometheus Alert Rule

```yaml
groups:
  - name: etcd
    rules:
      - alert: EtcdNoLeader
        expr: etcd_server_has_leader == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "etcd 리더 없음 — 클러스터 쓰기 불가"

      - alert: EtcdHighLeaderChanges
        expr: increase(etcd_server_leader_changes_seen_total[1h]) > 3
        labels:
          severity: warning
        annotations:
          summary: "etcd 리더 변경 빈번 (1시간 내 {{ $value }}회)"

      - alert: EtcdHighFsyncDuration
        expr: histogram_quantile(0.99, rate(etcd_disk_wal_fsync_duration_seconds_bucket[5m])) > 0.01
        labels:
          severity: warning
        annotations:
          summary: "etcd WAL fsync p99 지연 {{ $value | humanizeDuration }}"

      - alert: EtcdDbSizeHigh
        expr: etcd_mvcc_db_total_size_in_bytes / etcd_server_quota_backend_bytes > 0.75
        labels:
          severity: warning
        annotations:
          summary: "etcd DB 사용률 {{ $value | humanizePercentage }} — 컴팩션 필요"

      - alert: EtcdDbSizeCritical
        expr: etcd_mvcc_db_total_size_in_bytes / etcd_server_quota_backend_bytes > 0.90
        labels:
          severity: critical
        annotations:
          summary: "etcd DB 사용률 {{ $value | humanizePercentage }} — 즉시 조치 필요"

      - alert: EtcdMemberDown
        expr: up{job="etcd"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "etcd 멤버 다운: {{ $labels.instance }}"
```

### 2-3. Grafana 대시보드

- 공식 etcd 대시보드 ID: **`3070`** (Grafana.com)
- 추가 권장: etcd by Prometheus Community (`ID: 15308`)

---

## 3. 1차 진단 (First Response)

이슈 발생 시 **30초 내** 상황 파악을 위한 진단 순서입니다.

```bash
# 환경 변수 (TLS 환경 기준)
export ETCDCTL_API=3
export ETCDCTL_ENDPOINTS="https://etcd-1:2379,https://etcd-2:2379,https://etcd-3:2379"
export ETCDCTL_CACERT=/etc/etcd/pki/ca.crt
export ETCDCTL_CERT=/etc/etcd/pki/etcdctl.crt
export ETCDCTL_KEY=/etc/etcd/pki/etcdctl.key

# Step 1. 각 노드 상태 — 리더 확인, DB 크기, Revision
etcdctl endpoint status -w table

# Step 2. 알람 확인 (NOSPACE가 있으면 즉시 쓰기 중단됨)
etcdctl alarm list

# Step 3. 멤버 상태 확인 (unstarted/이탈 멤버)
etcdctl member list -w table

# Step 4. 최근 로그에서 핵심 키워드 필터
journalctl -u etcd --since "10 minutes ago" | \
  grep -E "slow|leader|quorum|NOSPACE|panic|took too long|failed to send"
```

**로그 메시지 해석표**

| 로그 메시지 | 원인 | 조치 |
|---|---|---|
| `apply entries took too long` | 디스크 I/O 병목 | ionice 조정, SSD 교체 검토 |
| `leader failed to send heartbeat` | 네트워크 지연 or 리더 과부하 | 피어 네트워크 점검 |
| `request timed out, possibly due to lost leader` | 쿼럼 손실 | 노드 수 확인, 재시작 시도 |
| `etcdserver: mvcc: database space exceeded` | NOSPACE | 즉시 compact + defrag |
| `raft: tocommit(X) is out of range` | 데이터 디렉토리 손상 | 멤버 제거 후 재추가 |
| `peer URLs already exists` | 중복 멤버 추가 | 기존 멤버 제거 후 재추가 |

---

## 4. 시나리오별 대응

### 시나리오 A: 리더 선출 불안정 / 잦은 리더 변경

**증상**: `etcd_server_leader_changes_seen_total` 증가, 간헐적 쓰기 지연

```bash
# 1. fsync 지연 확인 (가장 흔한 원인)
etcdctl endpoint status -w json | \
  jq '.[] | {ep: .Endpoint, leader: .Status.leader}'

# 2. 로그에서 지연 원인 확인
journalctl -u etcd | grep -E "took too long|fsync" | tail -20

# 3. 해당 노드의 I/O 경합 프로세스 확인
iostat -x 1 5
iotop -o -P
```

**대응 순서**:
1. `ionice -c 1 -n 0 -p $(pgrep etcd)` 로 etcd I/O 우선순위 최상위로 조정
2. 다른 프로세스(로그 수집기, 모니터링 에이전트)의 I/O 경합 제거
3. HDD 사용 중이라면 `--heartbeat-interval=200 --election-timeout=2000` 으로 완화
4. 근본 원인이 디스크라면 NVMe 마이그레이션 계획 수립

---

### 시나리오 B: NOSPACE 알람 → 쓰기 전면 거부

**증상**: kube-apiserver 오류, `etcdserver: mvcc: database space exceeded`

> **영향**: etcd에 쓰기가 불가해지므로 k8s 클러스터 전체 변경 불가 상태

```bash
# 현재 DB 크기 확인
etcdctl endpoint status -w json | \
  jq '.[] | {ep: .Endpoint, dbSizeMB: (.Status.dbSize / 1024 / 1024 | floor)}'

# NOSPACE 해결 절차 (순서 중요)

# 1. 현재 최신 Revision 확인
REV=$(etcdctl endpoint status --write-out=json | \
  jq '.[0].Status.header.revision')
echo "Compaction 대상 Revision: $REV"

# 2. 컴팩션 (Leader에서 실행 — 클러스터 전체에 적용됨)
etcdctl compact $REV

# 3. Defrag — Follower 먼저, Leader 마지막 (Leader defrag 중 쿼럼 손실 방지)
etcdctl defrag --endpoints=https://etcd-2:2379
etcdctl defrag --endpoints=https://etcd-3:2379
etcdctl defrag --endpoints=https://etcd-1:2379  # Leader 마지막

# 4. 알람 해제
etcdctl alarm disarm

# 5. 알람 해제 확인 (빈 응답이면 정상)
etcdctl alarm list

# 6. DB 크기 재확인
etcdctl endpoint status -w table
```

> **예방**: DB quota의 75% 도달 시 알람 → 정기 컴팩션 스케줄 유지 (cron)

---

### 시나리오 C: 단일 노드 이탈 (쿼럼 유지 상태)

**증상**: 특정 멤버 `unstarted` 또는 `unreachable`, 나머지 노드는 정상

```bash
# 이탈 멤버 확인
etcdctl member list -w table

# 원인 파악 (해당 노드에서)
journalctl -u etcd -n 100
df -h /var/lib/etcd   # 디스크 풀
dmesg | tail -30      # OOM, HW 오류

# 단순 재시작으로 복구 가능한 경우
systemctl restart etcd
etcdctl endpoint health   # 복구 확인

# 데이터 손상으로 재추가 필요한 경우
MEMBER_ID=$(etcdctl member list -w json | \
  jq -r '.members[] | select(.name=="etcd-3") | .ID')

# 기존 멤버 제거 (정상 노드에서 실행)
etcdctl member remove $MEMBER_ID

# 해당 노드에서 데이터 디렉토리 삭제
rm -rf /var/lib/etcd/*

# 새 멤버로 추가
etcdctl member add etcd-3 \
  --peer-urls=https://etcd-3:2380

# etcd 재시작 (--initial-cluster-state=existing 으로)
systemctl start etcd

# 동기화 완료 확인 (DB 크기가 다른 멤버와 비슷해질 때까지 대기)
watch -n 2 'etcdctl endpoint status -w table'
```

---

### 시나리오 D: 쿼럼 손실 (과반수 노드 다운)

**증상**: 모든 쓰기 요청 타임아웃, `request timed out, possibly due to lost leader`

> **영향**: k8s 클러스터 완전 정지. 신규 Pod 생성, ConfigMap 변경 등 모두 불가.

```bash
# 5노드 기준 3노드 이상 다운 시

# 방법 1: 다운된 노드 최대한 빨리 재시작 (데이터 손상 없는 경우)
systemctl start etcd  # 각 노드에서 순차 실행

# 방법 2: 스냅샷 복구 (데이터 손상 또는 복구 불가인 경우)

# 2-1. 가장 최신 스냅샷 선택
ls -lt /backups/etcd/*.db | head -5

# 2-2. 스냅샷 유효성 검증
etcdctl snapshot status /backups/etcd/latest.db -w table

# 2-3. 1개 노드에서 스냅샷으로 데이터 디렉토리 복원
etcdctl snapshot restore /backups/etcd/latest.db \
  --name=etcd-1 \
  --initial-cluster="etcd-1=https://etcd-1:2380,etcd-2=https://etcd-2:2380,etcd-3=https://etcd-3:2380" \
  --initial-cluster-token=etcd-cluster \
  --initial-advertise-peer-urls=https://etcd-1:2380 \
  --data-dir=/var/lib/etcd-restored

# 2-4. 나머지 노드에도 동일 스냅샷으로 복원 (각자 --name, --initial-advertise-peer-urls 변경)

# 2-5. 모든 노드에서 복원된 데이터 디렉토리로 etcd 기동
mv /var/lib/etcd /var/lib/etcd-old
mv /var/lib/etcd-restored /var/lib/etcd
systemctl start etcd

# --force-new-cluster는 단독 복구 시에만 사용 (데이터 손실 위험)
# 가능한 한 모든 노드 동시 복원 방식 사용
```

---

### 시나리오 E: 쓰기 지연 (High Write Latency)

**증상**: kube-apiserver 응답 지연, `etcd_disk_backend_commit_duration_seconds` p99 상승

```bash
# 현재 지연 확인
etcdctl endpoint status -w json | \
  jq '.[] | {ep: .Endpoint, dbSize: .Status.dbSize}'

# defrag로 DB 파일 내부 단편화 해소
# (단편화가 심하면 읽기/쓰기 모두 느려짐)
etcdctl defrag --endpoints=https://etcd-2:2379
etcdctl defrag --endpoints=https://etcd-3:2379
etcdctl defrag --endpoints=https://etcd-1:2379

# 개선 효과 확인
etcdctl endpoint status -w table  # dbSize 감소 확인
```

**Defrag 주의사항**:
- defrag 중 해당 노드는 일시적으로 응답 불가 (수 초 ~ 수십 초)
- **Follower 먼저, Leader 마지막** 순서 필수
- Leader defrag 중 선거가 발생할 수 있으므로 업무 영향 최소 시간대에 실행

---

## 5. 대규모 k8s 특화 고려사항

### 5-1. Event 오브젝트 전용 etcd 분리 (권장)

Event는 쓰기 빈도가 매우 높아 일반 오브젝트 etcd에 부하를 줍니다. **별도 etcd 클러스터로 분리**하는 것을 강력 권장합니다.

```bash
# kube-apiserver 플래그 추가
--etcd-servers-overrides=/events#https://etcd-events-1:2379,https://etcd-events-2:2379,https://etcd-events-3:2379
```

효과:
- 메인 etcd의 revision 증가 속도 감소 → 컴팩션 주기 여유
- Event 폭주로 인한 메인 etcd NOSPACE 방지
- Event etcd 장애가 클러스터 기능에 미치는 영향 격리

### 5-2. kube-apiserver 컴팩션 주기 단축

```bash
# kube-apiserver 플래그 (기본 5분 → 대규모 클러스터는 단축 권장)
--etcd-compaction-interval=3m
```

### 5-3. Lease 관리

k8s 노드 heartbeat는 Lease 오브젝트를 통해 etcd에 기록됩니다. 노드 수가 많을수록 Lease 쓰기가 집중됩니다.

```bash
# 현재 Lease 수 확인
etcdctl get /registry/leases --prefix --keys-only | wc -l

# 만료된 Lease 잔재 확인 (비정상적으로 많으면 gc 지연 의심)
etcdctl get /registry/leases/kube-node-lease --prefix --keys-only
```

### 5-4. 대규모 오브젝트 Key 모니터링

```bash
# etcd에서 가장 많은 키를 가진 prefix 확인
etcdctl get /registry --prefix --keys-only | \
  awk -F'/' '{print "/"$2"/"$3}' | sort | uniq -c | sort -rn | head -20
```

### 5-5. etcd 버전 업그레이드 절차 (롤링)

```bash
# 1. 업그레이드 전 스냅샷 백업 필수
etcdctl snapshot save /backups/etcd/pre-upgrade-$(date +%Y%m%d).db

# 2. Follower 순서로 1개씩 업그레이드
#    (새 바이너리로 교체 → 재시작 → 동기화 확인 → 다음 노드)
systemctl stop etcd
cp /usr/local/bin/etcd-new /usr/local/bin/etcd
systemctl start etcd
etcdctl endpoint status -w table  # 동기화 완료 확인

# 3. Leader 마지막 업그레이드
#    Leader 재시작 전 수동으로 리더십 이전 권장
etcdctl move-leader <follower-member-id>
```

---

## 6. 백업 및 복구 전략

### 6-1. 백업 정책

| 항목 | 권장값 |
|---|---|
| 스냅샷 주기 | 1시간 (최소 6시간) |
| 보관 기간 | 7일 로컬 + 30일 오브젝트 스토리지 |
| 백업 대상 노드 | Follower (Leader 부하 감소) |
| 스냅샷 파일 검증 | 저장 후 `etcdctl snapshot status` 자동 확인 |
| RTO 목표 | 30분 이내 (쿼럼 손실 기준) |
| RPO 목표 | 1시간 이내 데이터 손실 허용 |

### 6-2. 자동 백업 스크립트 (systemd timer 권장)

```bash
#!/bin/bash
# /usr/local/bin/etcd-backup.sh

BACKUP_DIR="/backups/etcd"
S3_BUCKET="s3://your-bucket/etcd-backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SNAPSHOT_FILE="$BACKUP_DIR/etcd-snapshot-$TIMESTAMP.db"

export ETCDCTL_API=3
ENDPOINTS="https://etcd-2:2379"  # Follower 지정
CACERT=/etc/etcd/pki/ca.crt
CERT=/etc/etcd/pki/etcdctl.crt
KEY=/etc/etcd/pki/etcdctl.key

mkdir -p "$BACKUP_DIR"

# 스냅샷 저장
etcdctl snapshot save "$SNAPSHOT_FILE" \
  --endpoints="$ENDPOINTS" \
  --cacert="$CACERT" --cert="$CERT" --key="$KEY"

# 유효성 검증
etcdctl snapshot status "$SNAPSHOT_FILE" -w table \
  --cacert="$CACERT" --cert="$CERT" --key="$KEY"

if [ $? -ne 0 ]; then
  echo "[ERROR] 스냅샷 검증 실패: $SNAPSHOT_FILE" | \
    systemd-cat -t etcd-backup -p err
  exit 1
fi

# S3 업로드 (aws cli 또는 minio mc)
aws s3 cp "$SNAPSHOT_FILE" "$S3_BUCKET/"

# 로컬 7일 보관 (오래된 파일 삭제)
find "$BACKUP_DIR" -name "*.db" -mtime +7 -delete

echo "[OK] etcd 백업 완료: $SNAPSHOT_FILE"
```

### 6-3. 복구 훈련 (Drill)

- **분기 1회** 실제 복구 절차 실습 필수
- 스테이징 환경에서 스냅샷 복원 → kube-apiserver 재연결 → 기능 확인
- Runbook을 팀 전체가 숙지하도록 공유 및 갱신

---

## 7. 정기 점검 체크리스트

### 일간

```bash
# 헬스 체크
etcdctl endpoint health
etcdctl endpoint status -w table

# 알람 확인
etcdctl alarm list

# DB 크기 추세 확인 (Grafana 또는 직접)
etcdctl endpoint status -w json | \
  jq '.[] | {ep: .Endpoint, dbSizeMB: (.Status.dbSize / 1024 / 1024 | floor)}'
```

### 주간

- 스냅샷 백업 파일 존재 및 검증 확인
- Prometheus 알람 이력 검토
- 리더 변경 횟수 확인

### 월간

- defrag 실행 (DB 파일 단편화 해소)
- 컴팩션 후 DB 크기 추세 점검
- etcd 버전 업그레이드 계획 검토
- 복구 훈련 (분기)

---

## 8. 인시던트 심각도 분류 및 Runbook

| 심각도 | 상황 | 대응 시간 목표 | 담당 |
|---|---|---|---|
| **P1 (Critical)** | 쿼럼 손실 — 클러스터 전체 정지 | 즉시 대응, 30분 내 복구 개시 | Incident Commander + On-call |
| **P1 (Critical)** | NOSPACE 알람 발생 | 5분 내 compact 시작 | On-call |
| **P2 (High)** | 단일 멤버 이탈 | 30분 내 재투입 | On-call |
| **P2 (High)** | 리더 변경 빈번 (1h 내 3회↑) | 15분 내 원인 파악 | On-call |
| **P3 (Medium)** | DB 크기 quota 75% 이상 | 2시간 내 compaction | On-call |
| **P3 (Medium)** | 쓰기 지연 증가 | 업무 시간 내 defrag | 담당자 |
| **P4 (Low)** | 스냅샷 백업 실패 | 익일 조치 | 담당자 |

### 에스컬레이션 기준

```
P1 발생 → 즉시 팀 전체 알림 (Slack/PagerDuty)
          15분 내 원인 미파악 → 시니어 엔지니어 에스컬레이션
          30분 내 복구 미완료 → 경영진 보고
```

---

## 참고 문서

- [etcd 트러블슈팅 가이드](../troubleshooting/troubleshooting-guide.md)
- [HA 클러스터 구성 및 멤버 교체](../operations/ha-guide.md)
- [스냅샷 백업 및 복구](../backup/backup-guide.md)
- [kube-apiserver ↔ etcd 요청 흐름](kube-apiserver-etcd-storage-guide.md)
- [etcd 공식 운영 가이드](https://etcd.io/docs/v3.5/op-guide/)
- [etcd 성능 벤치마킹](https://etcd.io/docs/v3.5/op-guide/performance/)
