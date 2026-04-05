# etcd 아키텍처 및 Raft 합의 알고리즘

---

## etcd란

etcd는 **분산 Key-Value 저장소**입니다. Kubernetes는 모든 클러스터 상태(Pod, Service, ConfigMap 등)를 etcd에 저장합니다.

```
etcd의 핵심 보장:
  ✓ 강한 일관성 (Strong Consistency)  — 모든 노드에서 동일한 데이터 조회
  ✓ 내결함성 (Fault Tolerance)         — 과반수 노드 살아있으면 동작
  ✓ Watch 기능                          — 키 변경 시 즉시 알림
  ✓ 원자적 트랜잭션                      — 비교 후 교체 (CAS)
```

---

## 전체 구조

```
                     클라이언트
                  (etcdctl / 앱 / k8s)
                         │
                    HTTP/gRPC :2379
                         │
          ┌──────────────┼──────────────┐
          │              │              │
     ┌────▼────┐    ┌────▼────┐   ┌────▼────┐
     │ etcd-1  │    │ etcd-2  │   │ etcd-3  │
     │ Leader  │◀──▶│Follower │◀──▶│Follower │
     │         │    │         │   │         │
     │ WAL     │    │ WAL     │   │ WAL     │
     │ Snapshot│    │ Snapshot│   │ Snapshot│
     └────┬────┘    └────┬────┘   └────┬────┘
          │              │              │
          └──────────────┴──────────────┘
                  Raft 피어 통신 :2380
```

---

## Raft 합의 알고리즘

etcd는 **Raft** 알고리즘으로 분산 합의를 달성합니다.

### 노드 역할

```
Leader   → 모든 쓰기 요청 처리, Follower에 로그 복제
Follower → Leader의 로그를 수신하여 적용, 읽기 가능
Candidate → Leader 선출 투표 중인 상태
```

### 리더 선출

```
정상 상태:
  Leader ──heartbeat──▶ Follower-1
  Leader ──heartbeat──▶ Follower-2

Leader 장애:
  Follower-1: heartbeat timeout 초과
              → Candidate 상태로 전환
              → 자신에게 투표
              → Follower-2에게 투표 요청
              → 과반수 획득 → Leader 당선

  새 Leader ──heartbeat──▶ 나머지 Follower
```

**선출 타임아웃**: 기본 1초 (heartbeat 100ms, election timeout 1000ms)

### 쓰기 흐름

```
클라이언트 ──PUT /key=value──▶ Leader
                                  │
                         1. WAL에 로그 기록
                                  │
                    ┌─────────────┼─────────────┐
                    │             │             │
              Follower-1    Follower-2    (Leader 자신)
              WAL 기록       WAL 기록
                    │             │
                    └─────────────┘
                          │
              과반수(2/3) ACK 수신
                          │
                  커밋 & 상태 머신 적용
                          │
              클라이언트에 성공 응답
```

### 쿼럼 (Quorum)

```
클러스터 크기  쿼럼 (과반수)  허용 장애 수
     1             1              0
     3             2              1
     5             3              2
     7             4              3
```

> **핵심 공식**: 쿼럼 = `floor(N/2) + 1`
>
> 3노드에서 2개 장애 → 쿼럼 미달 → 클러스터 동작 불가 (Split-brain 방지)

---

## 데이터 저장 구조

```
/var/lib/etcd/
├── member/
│   ├── snap/          ← 스냅샷 파일 (데이터베이스 파일)
│   │   ├── db         ← BoltDB (bbolt) 파일 — 실제 KV 데이터
│   │   └── 0000000000000001-0000000000000001.snap
│   └── wal/           ← Write-Ahead Log
│       └── 0000000000000000-0000000000000000.wal
```

### WAL (Write-Ahead Log)

- 모든 변경 사항을 먼저 WAL에 기록
- 장애 복구 시 WAL을 재생(replay)하여 상태 복원
- 주기적으로 스냅샷 생성 → 오래된 WAL 삭제

### BoltDB (bbolt)

- etcd 내부 스토리지 엔진
- B-tree 구조의 ACID 보장 Key-Value 스토어
- 모든 데이터를 하나의 파일(`db`)에 저장

---

## MVCC (Multi-Version Concurrency Control)

etcd는 모든 키의 변경 이력을 **Revision** 번호로 관리합니다.

```
Revision 1: PUT /foo = "a"
Revision 2: PUT /bar = "b"
Revision 3: PUT /foo = "c"   ← /foo의 최신값

etcdctl get /foo              → "c" (최신)
etcdctl get /foo --rev=1      → "a" (과거 조회)
```

**활용**:
- 클라이언트가 특정 Revision 이후 변경 사항만 Watch 가능
- Watch 중 연결이 끊겨도 Revision을 지정해 이어서 수신 가능

---

## 컴팩션 (Compaction)

오래된 Revision을 정리하여 디스크 공간을 확보합니다.

```bash
# 현재 Revision 확인
docker exec etcd etcdctl endpoint status --write-out=json | jq '.[0].Status.header.revision'

# 특정 Revision까지 컴팩션 (이전 버전 데이터 삭제)
docker exec etcd etcdctl compact <REVISION>

# 조각난 공간 정리 (컴팩션 후 실행)
docker exec etcd etcdctl defrag
```

> **운영 팁**: etcd는 기본적으로 자동 컴팩션을 지원합니다.
> `--auto-compaction-retention=1h` 플래그로 설정합니다.

---

## etcd와 Kubernetes

```
kube-apiserver ──gRPC──▶ etcd (엔드포인트)
                              │
                    모든 K8s 오브젝트 저장
                    (Pods, Services, ConfigMaps,
                     Secrets, Deployments ...)
```

Kubernetes etcd는 일반 etcd와 동일하지만:
- 기본적으로 TLS 암호화 필수
- 데이터 암호화 at-rest 지원 (`EncryptionConfig`)
- 컨트롤 플레인 HA = etcd 3중화 이상 권장

---

## 참고 링크

- [etcd 아키텍처 공식 문서](https://etcd.io/docs/v3.5/learning/api/)
- [Raft 논문](https://raft.github.io/raft.pdf)
- [Raft 시각화](https://raft.github.io/)
- [etcd MVCC 설명](https://etcd.io/docs/v3.5/learning/data_model/)
