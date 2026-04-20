# 문서 작성 원칙 — etcd-practice

## 언어
- 본문은 한국어, 기술 용어(etcdctl, snapshot, compaction)는 영어
- 서술체: `~다.`, `~한다.`

## 문서 구조
1. **개요** — 이 기능이 무엇을 해결하는지
2. **환경 설정** — Docker Compose 또는 etcdctl 환경변수
3. **명령어 예시** — 실제 동작 가능한 etcdctl 명령어
4. **상태 확인** — endpoint health/status
5. **트러블슈팅** — 쿼럼 손실, 디스크 풀

## 코드 블록
- etcdctl 명령어에 `ETCDCTL_API=3` 환경변수 명시
- `--endpoints` 플래그 항상 포함
- Docker Compose 환경에서 `docker exec` 방식 사용

## 주의사항
- 데이터 손실 위험: `> **데이터 주의**:`
- 쿼럼 손실 위험: `> **쿼럼 주의**:`
