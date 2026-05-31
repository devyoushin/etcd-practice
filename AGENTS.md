# AGENTS.md — etcd-practice Codex 작업 지침

이 저장소는 etcd 설치, 클러스터, 백업/복구, 운영 지식 베이스입니다. Codex 작업 시 `CLAUDE.md`와 `docs/rules/`의 규칙을 동일하게 따릅니다.

## 공통 원칙

- etcd 개념과 운영 설명은 `docs/`에 둡니다.
- Compose, systemd, 백업/복구/업그레이드 스크립트는 `ops/`에 둡니다.
- 업그레이드와 복구 절차는 snapshot 백업, quorum, rollback 가능성을 먼저 확인합니다.
- TLS, peer/client URL, advertise/listen URL은 예시에서 명확히 구분합니다.

## Claude와의 싱크

- Claude 작업 지침은 `CLAUDE.md`를 참고합니다.
- Codex도 문서/운영 규칙은 `docs/rules/`를 따릅니다.
- 구조 변경 시 `README.md`, `docs/README.md`, `ops/README.md`를 함께 확인합니다.

## 작업 체크리스트

- `git status --short` 확인
- shell script는 `bash -n` 검사
- Compose/YAML 파일은 문법 검사
- 링크 검사와 `git diff --check` 수행
