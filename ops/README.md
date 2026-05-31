# etcd Ops

etcd 운영 보조 자료와 실습 자산을 두는 공간입니다.

| 폴더 | 내용 |
|------|------|
| `install/` | 단일 노드 Compose와 systemd 설치 스크립트 |
| `upgrade/` | systemd 기반 etcd 업그레이드 스크립트 |
| `cluster/` | 클러스터 구성 예제 |
| `backup/` | 백업 스크립트 |
| `restore/` | 복구 스크립트 |
| `scripts/` | 점검과 자동화 스크립트 |

## 주요 파일

| 파일 | 내용 |
|------|------|
| `install/compose-single.yaml` | Docker Compose 기반 단일 노드 etcd |
| `install/install-etcd-systemd.sh` | systemd 기반 etcd 설치 스크립트 |
| `upgrade/upgrade-etcd-systemd.sh` | snapshot 백업 후 etcd 바이너리 업그레이드 |
| `cluster/compose-3node.yaml` | Docker Compose 기반 3중화 etcd 클러스터 |
| `backup/backup-etcd-docker.sh` | Docker 환경 snapshot 백업 스크립트 |
| `restore/restore-single-node.sh` | snapshot 단일 노드 복원 스크립트 |
| `scripts/etcd-healthcheck.sh` | endpoint health/status/member 점검 스크립트 |

etcd 원리를 설명하는 문서는 `docs/`에 두고, 실제 예시 파일과 운영 보조 자료는 `ops/`에 둡니다.
