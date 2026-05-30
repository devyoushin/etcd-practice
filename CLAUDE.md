# etcd-practice — 프로젝트 가이드

## 프로젝트 설정
- 환경: 로컬 (단일 호스트 다중 컨테이너)
- etcd 버전: v3.5.17
- 설치 방식: Docker / Docker Compose / systemd (바이너리)
- 클러스터: 3중화 (기본) / 5중화 (고가용성)

---

## 디렉토리 구조

```
etcd-practice/
├── CLAUDE.md                  # 이 파일 (자동 로드)
├── .claude/
│   ├── settings.json
│   └── commands/              # /new-doc, /new-runbook, /review-doc, /add-troubleshooting, /search-kb
├── docs/agents/                    # doc-writer, cluster-designer, troubleshooter, backup-advisor
├── docs/templates/                 # service-doc, runbook, incident-report
├── docs/rules/                     # doc-writing, etcd-conventions, security-checklist, monitoring
└── docs/                      # 주제별 가이드 문서
```

---

## 커스텀 슬래시 명령어

| 명령어 | 설명 | 사용 예시 |
|--------|------|---------|
| `/new-doc` | 새 가이드 문서 생성 | `/new-doc defragmentation` |
| `/new-runbook` | 새 런북 생성 | `/new-runbook etcd 멤버 교체` |
| `/review-doc` | 문서 검토 | `/review-doc docs/backup-guide.md` |
| `/add-troubleshooting` | 트러블슈팅 케이스 추가 | `/add-troubleshooting 쿼럼 손실` |
| `/search-kb` | 지식베이스 검색 | `/search-kb etcd 백업 복구` |

---

## 가이드 문서 목록

| 문서 | 주제 |
|------|------|
| `docs/install.md` | etcd 설치 (Docker Compose / systemd) |
| `docs/architecture-guide.md` | etcd 아키텍처 (Raft, WAL) |
| `docs/basic-operations-guide.md` | 기본 CRUD 및 Watch |
| `docs/cluster-guide.md` | 3노드 클러스터 구성 |
| `docs/ha-guide.md` | 5노드 HA 클러스터 |
| `docs/backup-guide.md` | 스냅샷 백업/복구 |
| `docs/troubleshooting-guide.md` | 트러블슈팅 |
| `docs/kube-apiserver-etcd-storage-guide.md` | kube-apiserver → etcd 요청 흐름 및 Key 저장 구조 |
| `docs/k8s-etcd-ops-guide.md` | 대규모 온프레미스 k8s 환경 etcd 이슈 대응 가이드 |

---

## 환경 변수 설정

```bash
export ETCDCTL_API=3
export ETCDCTL_ENDPOINTS="http://localhost:2379,http://localhost:2380,http://localhost:2381"

# 클러스터 상태 확인
etcdctl endpoint health
etcdctl endpoint status -w table
etcdctl member list -w table
```

---

## 쿼럼 원칙

| 멤버 수 | 쿼럼 | 허용 장애 수 |
|--------|------|------------|
| 3 | 2 | 1 |
| 5 | 3 | 2 |
| 7 | 4 | 3 |

**짝수 멤버 수는 절대 사용하지 않는다.**
