# etcd 코드 표준 관행

## etcdctl 환경변수 설정 (필수)

```bash
export ETCDCTL_API=3
export ETCDCTL_ENDPOINTS="http://etcd1:2379,http://etcd2:2379,http://etcd3:2379"
# TLS 사용 시
export ETCDCTL_CACERT=/etc/etcd/ca.crt
export ETCDCTL_CERT=/etc/etcd/client.crt
export ETCDCTL_KEY=/etc/etcd/client.key
```

## 클러스터 필수 설정

```yaml
# Docker Compose etcd 서비스 기본 플래그
command:
  - etcd
  - --name=etcd1
  - --data-dir=/var/lib/etcd
  - --listen-client-urls=http://0.0.0.0:2379
  - --advertise-client-urls=http://etcd1:2379
  - --listen-peer-urls=http://0.0.0.0:2380
  - --initial-advertise-peer-urls=http://etcd1:2380
  - --initial-cluster=etcd1=http://etcd1:2380,etcd2=http://etcd2:2380,etcd3=http://etcd3:2380
  - --initial-cluster-state=new
  - --initial-cluster-token=etcd-cluster-token
  - --auto-compaction-retention=1    # 1시간마다 자동 compaction
  - --quota-backend-bytes=8589934592 # 8GB 제한
```

## 쿼럼 원칙

| 멤버 수 | 쿼럼 | 허용 장애 |
|--------|------|---------|
| 3 | 2 | 1 |
| 5 | 3 | 2 |
| 7 | 4 | 3 |

**짝수 멤버 수는 절대 금지** — 분산 합의(split-brain) 위험

## 표준 확인 명령어

```bash
# 클러스터 상태 (필수)
etcdctl endpoint health --endpoints=$ETCDCTL_ENDPOINTS
etcdctl endpoint status --endpoints=$ETCDCTL_ENDPOINTS -w table

# 멤버 목록
etcdctl member list --endpoints=$ETCDCTL_ENDPOINTS -w table

# 알람 확인
etcdctl alarm list --endpoints=$ETCDCTL_ENDPOINTS
```

## 백업 필수 주기

```bash
# 스냅샷 저장 (리더에서 실행 권장)
etcdctl snapshot save /backup/etcd-$(date +%Y%m%d-%H%M%S).db

# 스냅샷 검증
etcdctl snapshot status /backup/<file>.db -w table
```

## 절대 하지 말 것
- 짝수 클러스터 멤버 수 운영
- `--quota-backend-bytes` 없이 운영 (기본 2GB 초과 시 alarm)
- 스냅샷 검증 없이 복구 절차 진행
- 운영 중 `etcdctl del` 대량 삭제 (트랜잭션 사용)
