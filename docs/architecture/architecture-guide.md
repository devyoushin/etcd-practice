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

## kube-apiserver → etcd 요청 처리 흐름

`kubectl apply -f pod.yaml` 을 실행했을 때 내부에서 일어나는 전체 과정입니다.

```
kubectl apply -f pod.yaml
        │
        ▼
kube-apiserver
  ① 인증 (Authentication)        — 누구인가? (cert, token, OIDC)
  ② 인가 (Authorization)         — 허용된 작업인가? (RBAC)
  ③ 어드미션 컨트롤 (Admission)   — 정책 검사 + 기본값 주입
  │   MutatingWebhook   → 오브젝트 변경 (예: label 자동 추가)
  │   ValidatingWebhook → 최종 유효성 검사
  ④ 직렬화 (Serialization)        — 오브젝트를 protobuf 바이너리로 인코딩
        │
        │ gRPC + TLS
        ▼
etcd Leader
  ⑤ WAL에 로그 기록
  ⑥ Follower들에 복제 → 과반수(쿼럼) ACK 수신
  ⑦ BoltDB(bbolt)에 커밋
        │
        ▼
kube-apiserver ← 성공 응답 반환
        │
        ▼
Watch 중인 컨트롤러들에 이벤트 push
  (Deployment Controller, Scheduler, kubelet 등)
```

> **핵심**: kubectl, 컨트롤러, 스케줄러 모두 etcd에 직접 접근하지 않습니다.
> **kube-apiserver가 etcd의 유일한 클라이언트**입니다.

---

## Kubernetes 오브젝트의 etcd Key 구조

### 키 패턴

```
/registry/<리소스종류>/<네임스페이스>/<이름>         ← 네임스페이스 스코프
/registry/<리소스종류>/<이름>                        ← 클러스터 스코프
```

### 전체 시뮬레이션 — 실제 etcd에 저장되는 Key 목록

```
/registry/
│
├── namespaces/
│   ├── default
│   ├── kube-system
│   ├── kube-public
│   └── production
│
├── nodes/
│   ├── master-node-1
│   ├── worker-node-1
│   └── worker-node-2
│
├── pods/
│   ├── default/
│   │   ├── my-nginx-pod
│   │   ├── my-backend-pod
│   │   └── debug-pod
│   └── kube-system/
│       ├── coredns-74ff55c5b-abc12
│       ├── kube-proxy-xyz99
│       └── etcd-master-node-1
│
├── deployments/apps/
│   ├── default/
│   │   ├── nginx-deployment
│   │   └── backend-deployment
│   └── production/
│       └── api-server-deployment
│
├── replicasets/apps/
│   ├── default/
│   │   ├── nginx-deployment-5d59d67564
│   │   └── nginx-deployment-7b9f8c6d45   ← 롤링 업데이트 시 이전 RS도 존재
│   └── production/
│       └── api-server-deployment-6c8d9e7f12
│
├── services/
│   ├── default/
│   │   ├── kubernetes                     ← 클러스터 기본 서비스
│   │   ├── nginx-service
│   │   └── backend-service
│   └── kube-system/
│       └── kube-dns
│
├── endpoints/
│   ├── default/
│   │   ├── kubernetes
│   │   └── nginx-service
│   └── kube-system/
│       └── kube-dns
│
├── configmaps/
│   ├── default/
│   │   └── app-config
│   └── kube-system/
│       ├── kube-proxy
│       ├── coredns
│       └── kubeadm-config
│
├── secrets/
│   ├── default/
│   │   ├── my-secret
│   │   └── default-token-xxxxx           ← ServiceAccount 토큰
│   └── kube-system/
│       ├── bootstrap-token-abcdef
│       └── etcd-certs
│
├── serviceaccounts/
│   ├── default/
│   │   └── default
│   └── kube-system/
│       ├── coredns
│       └── kube-proxy
│
├── persistentvolumes/
│   └── pv-nfs-001                        ← 클러스터 스코프 (네임스페이스 없음)
│
├── persistentvolumeclaims/
│   └── default/
│       └── my-pvc
│
├── ingresses/networking.k8s.io/
│   └── default/
│       └── my-ingress
│
├── roles/rbac.authorization.k8s.io/
│   └── default/
│       └── pod-reader
│
├── rolebindings/rbac.authorization.k8s.io/
│   └── default/
│       └── read-pods
│
├── clusterroles/rbac.authorization.k8s.io/
│   ├── cluster-admin
│   ├── view
│   └── edit
│
├── clusterrolebindings/rbac.authorization.k8s.io/
│   ├── cluster-admin
│   └── system:kube-scheduler
│
├── storageclasses/storage.k8s.io/
│   └── standard
│
├── leases/coordination.k8s.io/
│   └── kube-system/
│       ├── kube-controller-manager       ← 리더 선출용 락
│       └── kube-scheduler
│
└── events/
    ├── default/
    │   └── my-nginx-pod.17a1b2c3d4e5f6   ← Pod 이벤트 (TTL 있음)
    └── kube-system/
        └── coredns-74ff55c5b-abc12.17a1b2c3
```

### 실제 조회 방법

```bash
# 전체 키 목록 조회
etcdctl get /registry --prefix --keys-only

# 특정 리소스만 조회
etcdctl get /registry/pods --prefix --keys-only
etcdctl get /registry/pods/default --prefix --keys-only

# 특정 오브젝트 값 조회 (protobuf 바이너리)
etcdctl get /registry/pods/default/my-nginx-pod
```

---

## etcd에 저장되는 Value 구조

Value는 JSON이 아닌 **protobuf 바이너리**로 저장됩니다.

```
YAML 입력 (kubectl)
    │
    ▼ kube-apiserver 내부 처리
    │
    ├─ YAML → Go 구조체 (예: v1.Pod) 파싱
    ├─ Versioned Object → Internal Object 변환
    ├─ 기본값(defaulting) 채움
    └─ protobuf 직렬화
           │
           ▼ etcd에 저장되는 바이너리
    [ k8s\x00 헤더 (4byte) ][ APIVersion 정보 ][ protobuf bytes ]
```

```bash
# 실제 꺼내보면 깨진 문자 (protobuf binary)
etcdctl get /registry/pods/default/my-nginx-pod --print-value-only

# 앞 4바이트가 "k8s\x00" 매직 헤더임을 확인
etcdctl get /registry/pods/default/my-nginx-pod --print-value-only | xxd | head -3
# 00000000: 6b38 7300 0a0c ...
#           k  8  s  \0
```

---

## resourceVersion과 etcd Revision의 관계

`kubectl get pod my-nginx-pod -o yaml` 출력에서 보이는 `resourceVersion` 필드는 etcd의 revision 번호와 동일합니다.

```
etcd revision 흐름 (예시):

rev=1  : PUT /registry/namespaces/default
rev=2  : PUT /registry/serviceaccounts/default/default
rev=10 : PUT /registry/pods/default/my-nginx-pod        ← Pod 생성
rev=11 : PUT /registry/pods/default/my-nginx-pod        ← scheduler가 nodeName 할당
rev=15 : PUT /registry/pods/default/my-nginx-pod        ← kubelet이 Running 상태로 갱신
rev=30 : DEL /registry/pods/default/my-nginx-pod        ← Pod 삭제
```

```yaml
# kubectl get pod my-nginx-pod -o yaml 중 일부
metadata:
  resourceVersion: "15"    # ← etcd revision=15 과 동일
  uid: 3fa85f64-5717-4562-b3fc-2c963f66afa6
```

> **낙관적 잠금(Optimistic Locking)**: kube-apiserver가 오브젝트를 업데이트할 때
> `resourceVersion`이 일치하지 않으면 `409 Conflict`를 반환합니다.
> 이를 통해 동시 수정 충돌을 방지합니다.

---

## 참고 링크

- [etcd 아키텍처 공식 문서](https://etcd.io/docs/v3.5/learning/api/)
- [Raft 논문](https://raft.github.io/raft.pdf)
- [Raft 시각화](https://raft.github.io/)
- [etcd MVCC 설명](https://etcd.io/docs/v3.5/learning/data_model/)
- [kube-apiserver → etcd 요청 처리 및 저장 구조](../kubernetes/kube-apiserver-etcd-storage-guide.md)
