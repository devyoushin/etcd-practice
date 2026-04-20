etcd 트러블슈팅 케이스를 추가합니다.

**사용법**: `/add-troubleshooting <증상 설명>`

**예시**: `/add-troubleshooting etcd 클러스터 쿼럼 손실`

다음 형식으로 작성하고 `troubleshooting-guide.md`에 추가하세요:

```markdown
### <증상>

**원인**: <근본 원인>

**확인 방법**:
\`\`\`bash
etcdctl endpoint health --endpoints=<endpoints>
etcdctl endpoint status --endpoints=<endpoints> -w table
etcdctl alarm list
\`\`\`

**해결**: <해결 방법 — 스냅샷 복구 포함>
**예방**: <모니터링 및 정기 백업 설정>
```
