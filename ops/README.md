# etcd Ops

etcd를 실제로 설치하거나 실습할 때 사용하는 Docker Compose 예제, 설치/업그레이드/백업/복원 스크립트, 점검 스크립트를 두는 공간입니다. 개념 설명은 `docs/`에, 적용 가능한 실행 자산은 `ops/`에 둡니다.

## 폴더 구조

| 폴더 | 내용 |
|------|------|
| `install/` | Helm, Docker Compose, systemd 설치 예시 |
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
| `install/install-etcd-helm.sh` | Bitnami Helm Chart 기반 etcd 설치 스크립트 |
| `upgrade/upgrade-etcd-systemd.sh` | snapshot 백업 후 etcd 바이너리 업그레이드 |
| `cluster/compose-3node.yaml` | Docker Compose 기반 3중화 etcd 클러스터 |
| `backup/backup-etcd-docker.sh` | Docker 환경 snapshot 백업 스크립트 |
| `restore/restore-single-node.sh` | snapshot 단일 노드 복원 스크립트 |
| `scripts/etcd-healthcheck.sh` | endpoint health/status/member 점검 스크립트 |

## 관련 문서

| 작업 | 문서 |
|------|------|
| 설치 방식 선택 | [../docs/install/install.md](../docs/install/install.md) |
| 업그레이드 | [../docs/install/upgrade/README.md](../docs/install/upgrade/README.md) |
| 클러스터 구성 | [../docs/cluster/cluster-guide.md](../docs/cluster/cluster-guide.md) |
| 백업/복구 | [../docs/backup/backup-guide.md](../docs/backup/backup-guide.md) |
| HA 운영 | [../docs/operations/ha-guide.md](../docs/operations/ha-guide.md) |
| 트러블슈팅 | [../docs/troubleshooting/troubleshooting-guide.md](../docs/troubleshooting/troubleshooting-guide.md) |

## 관리 원칙

- 재사용 가능한 Compose 파일과 스크립트는 이 디렉터리에 둡니다.
- 문서 본문에는 핵심 스니펫만 넣고, 전체 적용 파일은 `ops/`를 기준으로 관리합니다.
- 실제 운영 인증서, 토큰, 백업 데이터는 커밋하지 않습니다.
