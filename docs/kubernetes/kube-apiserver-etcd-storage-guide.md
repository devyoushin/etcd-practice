# kube-apiserver → etcd 요청 처리 및 저장 구조

---

## 개요

Kubernetes의 모든 상태는 etcd에 저장됩니다. 하지만 kubectl, 컨트롤러, 스케줄러 중 어느 것도 etcd에 직접 접근하지 않습니다. **kube-apiserver가 etcd의 유일한 클라이언트**이며, 모든 읽기/쓰기는 반드시 kube-apiserver를 통해 이루어집니다.

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

# 키 개수 확인
etcdctl get /registry --prefix --keys-only | wc -l
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

## Watch 메커니즘

etcd의 Watch API를 통해 컨트롤러들이 변경 이벤트를 실시간으로 수신합니다.

```
kube-controller-manager / kube-scheduler / kubelet
        │
        │  gRPC WatchRequest (prefix: /registry/pods)
        ▼
etcd: 새 revision 발생 시 → 구독 중인 클라이언트에 즉시 이벤트 push
        │
        ├─ Scheduler: "새 Pod 발견, nodeName 없음 → 스케줄링 시작"
        ├─ Deployment Controller: "ReplicaSet 상태 확인 → 필요 시 Pod 생성"
        └─ kubelet: "내 노드에 할당된 Pod 발견 → 컨테이너 기동"
```

```bash
# etcdctl로 Watch 직접 실행
etcdctl watch /registry/pods --prefix

# 특정 키만 Watch
etcdctl watch /registry/pods/default/my-nginx-pod
```

---

## 상태 확인 명령어

```bash
# etcd 클러스터 상태 확인
etcdctl endpoint health
etcdctl endpoint status -w table
etcdctl member list -w table

# 전체 키 개수 확인 (클러스터 규모 파악)
etcdctl get /registry --prefix --keys-only | wc -l

# 리소스별 키 개수
etcdctl get /registry/pods --prefix --keys-only | wc -l
etcdctl get /registry/secrets --prefix --keys-only | wc -l
etcdctl get /registry/events --prefix --keys-only | wc -l
```

---

## 트러블슈팅

### etcd에서 오브젝트가 조회되지 않는 경우

```bash
# API 버전 확인
export ETCDCTL_API=3

# 엔드포인트 확인
export ETCDCTL_ENDPOINTS="http://localhost:2379"

# 키 존재 여부 확인
etcdctl get /registry/pods/default/my-nginx-pod --print-value-only | wc -c
# 0이면 키 없음
```

### 클러스터 크기 급증 시 (events 누적)

etcd에서 `events`는 TTL이 있지만 대량 이벤트가 쌓이면 DB 크기가 커집니다.

```bash
# events 키 개수 확인
etcdctl get /registry/events --prefix --keys-only | wc -l

# 현재 DB 크기 확인
etcdctl endpoint status -w table
# DB SIZE 컬럼 확인

# 컴팩션 후 조각 정리
REVISION=$(etcdctl endpoint status --write-out=json | jq '.[0].Status.header.revision')
etcdctl compact $REVISION
etcdctl defrag
```

### resourceVersion 충돌 (409 Conflict)

동일 오브젝트를 동시에 수정할 때 발생합니다.

```
원인: 두 클라이언트가 같은 resourceVersion으로 PUT 시도
해결: 최신 오브젝트를 다시 GET한 뒤 재시도 (kube-apiserver가 자동 처리)
```

---

## 참고 링크

- [Kubernetes etcd 데이터 모델](https://etcd.io/docs/v3.5/learning/data_model/)
- [kube-apiserver 요청 처리 흐름](https://kubernetes.io/docs/reference/access-authn-authz/controlling-access/)
- [Kubernetes API 개념 - resourceVersion](https://kubernetes.io/docs/reference/using-api/api-concepts/#resource-versions)
