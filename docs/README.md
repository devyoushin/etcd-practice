# etcd Docs

이 디렉터리는 목적별 번호 폴더로 문서를 관리합니다. 앞의 번호는 권장 학습 및 운영 참조 순서를 나타냅니다.

## 문서 구조

| 폴더 | 내용 |
|------|------|
| `01-installation/` | etcd 설치와 업그레이드 절차를 다룹니다. |
| `02-architecture/` | Raft, member, quorum, 데이터 모델 등 etcd 아키텍처를 다룹니다. |
| `03-cluster/` | 클러스터 구성, member 관리, 스케일링 기준을 다룹니다. |
| `04-backup-restore/` | 스냅샷, 백업, 복구, 재해 복구 절차를 다룹니다. |
| `05-kubernetes/` | Kubernetes control plane과 etcd 연동, 운영 기준을 다룹니다. |
| `06-operations/` | 모니터링, 성능, 압축, defrag, 장애 대응을 다룹니다. |
| `07-troubleshooting/` | 장애 상황별 진단과 해결 절차를 다룹니다. |
| `90-standards/` | 문서 작성과 etcd 운영 규칙을 다룹니다. |
| `91-templates/` | 재사용 문서 템플릿을 둡니다. |
| `99-agents/` | AI 작업 보조 프롬프트를 둡니다. |

실행 가능한 예제와 운영 보조 자료는 [../ops/README.md](../ops/README.md)를 참고합니다.
