etcd 가이드 문서를 검토합니다.

**사용법**: `/review-doc <파일 경로>`

**예시**: `/review-doc backup-guide.md`

검토 기준:

**클러스터 설정**
- [ ] 홀수 멤버 수 (3, 5) — 짝수 금지
- [ ] `--quota-backend-bytes` 설정 (기본 2GB, 최대 8GB)
- [ ] `--auto-compaction-retention` 설정
- [ ] TLS 설정 (peer, client 모두)

**백업**
- [ ] 정기 스냅샷 스케줄 (etcdctl snapshot save)
- [ ] 스냅샷 S3/외부 저장소 보관
- [ ] `etcdctl snapshot status`로 검증

**문서 품질**
- [ ] etcdctl 명령어에 --endpoints 플래그 명시
- [ ] ETCDCTL_API=3 환경변수 설명
- [ ] 쿼럼 손실 시나리오 및 복구 방법
