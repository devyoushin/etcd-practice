# etcd 실습 저장소

Docker로 etcd를 설치하고 단일 노드부터 5중화 클러스터까지 학습하는 실습 저장소입니다.

---

## 환경 정보

| 항목 | 값 |
|---|---|
| 설치 방식 | Docker / Docker Compose |
| etcd 버전 | `v3.5.x` 권장 |
| 실습 환경 | 로컬 (단일 호스트 다중 컨테이너) 또는 다중 서버 |

---

## 빠른 시작 (단일 노드)

```bash
# etcd 단일 노드 실행
docker run -d \
  --name etcd \
  -p 2379:2379 \
  quay.io/coreos/etcd:v3.5.17 \
  etcd \
  --advertise-client-urls http://0.0.0.0:2379 \
  --listen-client-urls http://0.0.0.0:2379

# 동작 확인
docker exec etcd etcdctl endpoint health
docker exec etcd etcdctl put hello world
docker exec etcd etcdctl get hello
```

---

## 학습 경로

### 1단계: 설치
- [Docker로 etcd 설치](./install.md)

### 2단계: 핵심 개념
- [아키텍처 및 Raft 합의 알고리즘](./architecture-guide.md)
- [기본 KV 조작](./basic-operations-guide.md)

### 3단계: 클러스터링 (핵심)
- [3중화 클러스터](./cluster-guide.md)
- [5중화 클러스터](./cluster-guide.md#5중화-클러스터)
- [고가용성 운영](./ha-guide.md)

### 4단계: 운영
- [백업 및 복원](./backup-guide.md)
- [트러블슈팅](./troubleshooting-guide.md)

---

## 저장소 구조

```
etcd-practice/
├── README.md
├── install.md                  # Docker로 etcd 설치
├── architecture-guide.md       # 아키텍처 및 Raft 합의
├── basic-operations-guide.md   # KV 조작, Watch, Lease, Transaction
├── cluster-guide.md            # 3중화 / 5중화 클러스터 구성
├── ha-guide.md                 # 고가용성 운영 (멤버 교체, 장애 복구)
├── backup-guide.md             # 스냅샷 백업 및 복원
└── troubleshooting-guide.md    # 트러블슈팅
```

---

## 클러스터 크기 요약

```
클러스터 크기 선택 기준:

  1 노드 → 개발/테스트용. 장애 허용 없음.

  3 노드 → 운영 최소 권장
            허용 장애: 1개 노드
            쿼럼: 2개 이상 정상
            write quorum: ceil(3/2) = 2

  5 노드 → 운영 고가용성 권장
            허용 장애: 2개 노드
            쿼럼: 3개 이상 정상
            write quorum: ceil(5/2) = 3

  7 노드 → 대규모 환경 (지연 증가, 잘 사용 안 함)
```

> **홀수 원칙**: 클러스터는 반드시 **홀수** 노드로 구성합니다.
> 4노드는 장애 허용 범위가 3노드와 동일(1개)하면서 비용만 증가합니다.

---

## 아키텍처 요약

```
┌─────────┐    ┌─────────┐    ┌─────────┐
│ etcd-1  │◀──▶│ etcd-2  │◀──▶│ etcd-3  │
│(Leader) │    │(Follower│    │(Follower│
│ :2379   │    │ :2379   │    │ :2379   │
│ :2380   │    │ :2380   │    │ :2380   │
└────┬────┘    └────┬────┘    └────┬────┘
     │              │              │
     └──────────────┴──────────────┘
              Raft 합의 프로토콜
              (peer port: 2380)

클라이언트 요청 → 어느 노드든 수신 가능
                → Leader가 아니면 Leader로 전달
                → Leader가 Raft로 과반수에 복제
                → 성공 응답
```

| 포트 | 용도 |
|---|---|
| `2379` | 클라이언트 통신 (etcdctl, 애플리케이션) |
| `2380` | 피어 통신 (클러스터 내 노드 간 Raft) |

---

## 참고 링크

- [etcd 공식 문서](https://etcd.io/docs/)
- [etcd v3.5 릴리즈 노트](https://github.com/etcd-io/etcd/releases)
- [etcd 운영 가이드](https://etcd.io/docs/v3.5/op-guide/)
- [Raft 합의 알고리즘](https://raft.github.io/)
