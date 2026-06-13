# etcd-practice

Helm, systemd, Docker Compose로 etcd를 설치하고 단일 노드부터 5중화 클러스터, 백업/복구, Kubernetes 연동, 장애 대응까지 학습하는 실습 저장소입니다.

## 먼저 볼 문서

| 목적 | 문서 |
|------|------|
| 전체 문서 목차 보기 | [docs/README.md](docs/README.md) |
| etcd 설치하기 | [docs/install/install.md](docs/install/install.md) |
| 아키텍처와 Raft 이해하기 | [docs/architecture/architecture-guide.md](docs/architecture/architecture-guide.md) |
| 기본 KV 조작하기 | [docs/operations/basic-operations-guide.md](docs/operations/basic-operations-guide.md) |
| 3/5노드 클러스터 구성하기 | [docs/cluster/cluster-guide.md](docs/cluster/cluster-guide.md) |
| 백업과 복구 익히기 | [docs/backup/backup-guide.md](docs/backup/backup-guide.md) |
| Kubernetes etcd 운영 보기 | [docs/kubernetes/k8s-etcd-ops-guide.md](docs/kubernetes/k8s-etcd-ops-guide.md) |
| 운영 자산 확인하기 | [ops/README.md](ops/README.md) |

## 추천 학습 순서

1. [etcd 설치](docs/install/install.md)
2. [아키텍처 및 Raft](docs/architecture/architecture-guide.md)
3. [기본 KV 조작](docs/operations/basic-operations-guide.md)
4. [클러스터 구성](docs/cluster/cluster-guide.md)
5. [고가용성 운영](docs/operations/ha-guide.md)
6. [백업 및 복원](docs/backup/backup-guide.md)
7. [Kubernetes etcd 저장 구조](docs/kubernetes/kube-apiserver-etcd-storage-guide.md)
8. [대규모 Kubernetes etcd 운영](docs/kubernetes/k8s-etcd-ops-guide.md)
9. [트러블슈팅](docs/troubleshooting/troubleshooting-guide.md)

## 디렉터리 구조

```text
etcd-practice/
├── README.md
├── CLAUDE.md          # AI 작업 지침
├── docs/
│   ├── README.md     # 문서 전체 목차
│   ├── install/      # 설치와 업그레이드
│   ├── architecture/ # etcd 구조, Raft, MVCC
│   ├── operations/   # 기본 명령, HA 운영
│   ├── cluster/      # 3/5노드 클러스터 구성
│   ├── backup/       # 스냅샷 백업과 복원
│   ├── kubernetes/   # kube-apiserver 저장 구조와 k8s 운영
│   ├── troubleshooting/ # 장애 진단
│   ├── agents/       # AI 역할별 작업 지침
│   ├── rules/        # 문서/운영 규칙
│   └── templates/    # 서비스 문서, 런북, 장애 보고서 템플릿
└── ops/
    ├── README.md
    ├── install/
    ├── upgrade/
    ├── cluster/
    ├── backup/
    ├── restore/
    └── scripts/
```

## 환경 정보

| 항목 | 값 |
|---|---|
| 설치 방식 | Helm / systemd / Docker Compose |
| etcd 버전 | `v3.5.x` 권장 |
| 실습 환경 | 로컬 단일 호스트 다중 컨테이너 또는 다중 서버 |

## 클러스터 크기 요약

| 멤버 수 | 쿼럼 | 허용 장애 수 | 용도 |
|---|---:|---:|---|
| 1 | 1 | 0 | 개발/테스트 |
| 3 | 2 | 1 | 운영 최소 권장 |
| 5 | 3 | 2 | 운영 고가용성 권장 |

클러스터는 홀수 멤버 수로 구성합니다. 4노드는 장애 허용 범위가 3노드와 동일하면서 비용만 증가합니다.
