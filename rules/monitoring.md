# 모니터링 지침 — etcd-practice

## 핵심 확인 명령어

```bash
# 클러스터 전체 상태
etcdctl endpoint health --endpoints=$ETCDCTL_ENDPOINTS
etcdctl endpoint status --endpoints=$ETCDCTL_ENDPOINTS -w table

# 리더 확인
etcdctl endpoint status --endpoints=$ETCDCTL_ENDPOINTS -w table | grep true

# DB 크기 확인
etcdctl endpoint status --endpoints=$ETCDCTL_ENDPOINTS -w json \
  | python3 -c "import sys,json; [print(f\"{e['Endpoint']}: {e['Status']['dbSize']/1024/1024:.1f}MB\") for e in json.load(sys.stdin)]"

# 알람 확인
etcdctl alarm list --endpoints=$ETCDCTL_ENDPOINTS
```

## Prometheus 메트릭 (etcd 내장)

| 메트릭 | 설명 | 알람 조건 |
|--------|------|---------|
| `etcd_mvcc_db_total_size_in_bytes` | DB 크기 | > quota의 80% |
| `etcd_disk_wal_fsync_duration_seconds` | WAL fsync 레이턴시 | p99 > 10ms |
| `etcd_disk_backend_commit_duration_seconds` | 백엔드 커밋 레이턴시 | p99 > 25ms |
| `etcd_server_leader_changes_seen_total` | 리더 변경 수 | > 3/시간 |
| `etcd_server_proposals_failed_total` | 제안 실패 수 | > 0 |

## 정기 유지보수

```bash
# Compaction (주기적 실행)
REVISION=$(etcdctl endpoint status --endpoints=$ETCDCTL_ENDPOINTS \
  -w json | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['Status']['header']['revision'])")
etcdctl compact $REVISION --endpoints=$ETCDCTL_ENDPOINTS

# Defrag (compaction 후)
etcdctl defrag --endpoints=$ETCDCTL_ENDPOINTS

# 알람 해제
etcdctl alarm disarm --endpoints=$ETCDCTL_ENDPOINTS
```
