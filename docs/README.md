# etcd Docs

etcd를 처음 보는 사람이 설치, 아키텍처, 기본 명령, 클러스터링, 백업/복구, Kubernetes 운영, 트러블슈팅까지 순서대로 따라갈 수 있도록 정리한 문서 디렉터리입니다.

## 빠른 길잡이

| 지금 하고 싶은 일 | 열 문서 |
|------|------|
| 설치 방식 고르기 | [install/install.md](install/install.md) |
| 업그레이드 절차 보기 | [install/upgrade/README.md](install/upgrade/README.md) |
| etcd 구조와 Raft 이해하기 | [architecture/architecture-guide.md](architecture/architecture-guide.md) |
| etcdctl 기본 명령 익히기 | [operations/basic-operations-guide.md](operations/basic-operations-guide.md) |
| 3/5노드 클러스터 구성하기 | [cluster/cluster-guide.md](cluster/cluster-guide.md) |
| HA 운영과 멤버 교체 보기 | [operations/ha-guide.md](operations/ha-guide.md) |
| 스냅샷 백업과 복구하기 | [backup/backup-guide.md](backup/backup-guide.md) |
| Kubernetes 오브젝트 저장 구조 이해하기 | [kubernetes/kube-apiserver-etcd-storage-guide.md](kubernetes/kube-apiserver-etcd-storage-guide.md) |
| 대규모 Kubernetes etcd 이슈 대응하기 | [kubernetes/k8s-etcd-ops-guide.md](kubernetes/k8s-etcd-ops-guide.md) |
| 장애를 진단하기 | [troubleshooting/troubleshooting-guide.md](troubleshooting/troubleshooting-guide.md) |

## 추천 읽기 순서

| 순서 | 문서 | 핵심 내용 |
|------|------|------|
| 1 | [install/install.md](install/install.md) | Helm, Docker Compose, systemd 설치 |
| 2 | [architecture/architecture-guide.md](architecture/architecture-guide.md) | Raft, WAL, MVCC, Kubernetes 저장 구조 |
| 3 | [operations/basic-operations-guide.md](operations/basic-operations-guide.md) | Put/Get/Delete, Watch, Lease, Txn |
| 4 | [cluster/cluster-guide.md](cluster/cluster-guide.md) | 3/5노드 클러스터 구성 |
| 5 | [operations/ha-guide.md](operations/ha-guide.md) | 멤버 교체, 리더 이전, 쿼럼 손실 복구 |
| 6 | [backup/backup-guide.md](backup/backup-guide.md) | 스냅샷 백업, 복원, defrag |
| 7 | [kubernetes/kube-apiserver-etcd-storage-guide.md](kubernetes/kube-apiserver-etcd-storage-guide.md) | kube-apiserver 요청 처리와 key 구조 |
| 8 | [kubernetes/k8s-etcd-ops-guide.md](kubernetes/k8s-etcd-ops-guide.md) | 대규모 k8s etcd 운영 이슈 대응 |
| 9 | [troubleshooting/troubleshooting-guide.md](troubleshooting/troubleshooting-guide.md) | 증상별 문제 해결 |

## 전체 문서 목록

| 구분 | 문서 |
|------|------|
| 설치 | [install/install.md](install/install.md), [install/upgrade/README.md](install/upgrade/README.md) |
| 아키텍처 | [architecture/architecture-guide.md](architecture/architecture-guide.md) |
| 운영 명령 | [operations/basic-operations-guide.md](operations/basic-operations-guide.md), [operations/ha-guide.md](operations/ha-guide.md) |
| 클러스터 | [cluster/cluster-guide.md](cluster/cluster-guide.md) |
| 백업/복구 | [backup/backup-guide.md](backup/backup-guide.md) |
| Kubernetes | [kubernetes/kube-apiserver-etcd-storage-guide.md](kubernetes/kube-apiserver-etcd-storage-guide.md), [kubernetes/k8s-etcd-ops-guide.md](kubernetes/k8s-etcd-ops-guide.md) |
| 트러블슈팅 | [troubleshooting/troubleshooting-guide.md](troubleshooting/troubleshooting-guide.md) |
| 문서 운영 | [rules/README.md](rules/README.md), [templates/README.md](templates/README.md), [agents/README.md](agents/README.md) |
| 실행 자산 | [../ops/README.md](../ops/README.md) |

## 폴더 역할

| 폴더 | 역할 |
|------|------|
| [install/](install/README.md) | 설치와 업그레이드 |
| [architecture/](architecture/README.md) | etcd 구조, Raft, WAL, MVCC |
| [operations/](operations/README.md) | 기본 운영 명령과 HA 운영 |
| [cluster/](cluster/README.md) | 3/5노드 클러스터 구성 |
| [backup/](backup/README.md) | 스냅샷 백업, 복원, defrag |
| [kubernetes/](kubernetes/README.md) | Kubernetes etcd 저장 구조와 운영 |
| [troubleshooting/](troubleshooting/README.md) | 장애 진단과 문제 해결 |

## 관리 원칙

- 설치는 `install/`, 구조 설명은 `architecture/`, 클러스터 구성은 `cluster/`에 둡니다.
- 기본 운영과 HA 절차는 `operations/`, 백업/복구는 `backup/`, Kubernetes 특화 내용은 `kubernetes/`에 둡니다.
- 실제 실행 가능한 Compose, 설치/백업/복원 스크립트는 `ops/`에 둡니다.
