새 etcd 가이드 문서를 생성합니다.

**사용법**: `/new-doc <주제명>`

**예시**: `/new-doc defragmentation`

주제 분류:
- 클러스터: cluster, ha, member-management
- 운영: backup, restore, defrag, compaction
- 관찰가능성: metrics, alerts, monitoring
- 보안: tls, rbac, auth

`<주제명>-guide.md` 생성 시 포함 내용:
- CLAUDE.md 환경 설정 반영 (etcd 버전, 클러스터 구성)
- Docker Compose 또는 etcdctl 명령어 예시
- 상태 확인 명령어 (etcdctl endpoint health)
- 트러블슈팅 섹션
