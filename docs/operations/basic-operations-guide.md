# 기본 KV 조작

---

## etcdctl 기본 설정

```bash
# 단일 노드 접속 alias 설정 (편의용)
alias etcdctl='docker exec etcd etcdctl'

# 클러스터 접속 (엔드포인트 여러 개 지정)
alias etcdctl='docker exec etcd etcdctl \
  --endpoints=http://etcd-1:2379,http://etcd-2:2379,http://etcd-3:2379'
```

---

## Put / Get / Delete

```bash
# 키 저장
etcdctl put /myapp/config/env production
etcdctl put /myapp/config/port 8080
etcdctl put /myapp/user/alice "Alice Kim"

# 키 조회
etcdctl get /myapp/config/env

# 출력: 키와 값을 함께 표시
# /myapp/config/env
# production

# 값만 출력
etcdctl get /myapp/config/env --print-value-only

# 범위 조회 (prefix)
etcdctl get /myapp/config/ --prefix

# 모든 키 조회
etcdctl get "" --prefix

# 키 삭제
etcdctl del /myapp/config/env

# prefix 일괄 삭제
etcdctl del /myapp/config/ --prefix

# 삭제된 키 수 반환
etcdctl del /myapp/ --prefix
```

---

## Revision 기반 조회

```bash
# 현재 클러스터 Revision 확인
etcdctl endpoint status --write-out=table

# 특정 Revision 시점의 값 조회
etcdctl get /myapp/config/env --rev=5

# 키의 변경 이력 조회
etcdctl get /myapp/config/env \
  --write-out=json | jq '.kvs[0].mod_revision'
```

---

## Watch (변경 감지)

키의 변경을 실시간으로 감지합니다. Kubernetes가 etcd 변경을 감지하는 방식과 동일합니다.

```bash
# 특정 키 Watch (변경 시 즉시 출력)
etcdctl watch /myapp/config/env

# 다른 터미널에서 값 변경
etcdctl put /myapp/config/env staging
# → Watch 터미널에 즉시 출력됨

# prefix 전체 Watch
etcdctl watch /myapp/ --prefix

# 특정 Revision 이후부터 Watch (이벤트 재수신)
etcdctl watch /myapp/config/env --rev=3

# Watch 결과를 스크립트로 처리
etcdctl watch /myapp/config/ --prefix | while read line; do
  echo "변경 감지: $line"
  # 여기에 처리 로직 추가
done
```

---

## Lease (TTL)

키에 만료 시간을 설정합니다. 세션, 분산 락, 서비스 등록 등에 활용합니다.

```bash
# Lease 생성 (30초 TTL)
LEASE_ID=$(etcdctl lease grant 30 | awk '{print $2}')
echo "Lease ID: $LEASE_ID"

# Lease에 키 연결
etcdctl put /myapp/session/user-123 "active" --lease=$LEASE_ID

# Lease 정보 확인
etcdctl lease timetolive $LEASE_ID

# Lease 갱신 (keep-alive) — Lease가 만료되지 않도록 주기적 갱신
etcdctl lease keep-alive $LEASE_ID

# Lease 조기 해지 (연결된 키 모두 삭제)
etcdctl lease revoke $LEASE_ID

# 30초 후 자동 만료 확인
etcdctl get /myapp/session/user-123   # 빈 응답 (삭제됨)
```

### Lease 활용 예시: 분산 락

```bash
# 락 획득 (Lease 기반)
LEASE_ID=$(etcdctl lease grant 10 | awk '{print $2}')

# 락 키가 없으면 생성 (원자적 비교-교체)
etcdctl put /locks/my-resource "holder-1" \
  --lease=$LEASE_ID \
  --prev-kv   # 이전 값 반환

# 작업 수행 중 Lease 갱신
etcdctl lease keep-alive $LEASE_ID &

# 작업 완료 후 락 해제
etcdctl lease revoke $LEASE_ID
```

---

## Transaction (원자적 조작)

Compare-And-Swap (CAS) — 조건 검사 후 쓰기를 원자적으로 수행합니다.

```bash
# 문법:
# etcdctl txn <<EOF
# compare 조건
#
# 조건 참일 때 실행할 명령
#
# 조건 거짓일 때 실행할 명령
# EOF

# 예시: /counter가 "0"이면 "1"로 변경, 아니면 현재 값 반환
etcdctl txn <<EOF
value("/counter") = "0"

put /counter "1"

get /counter
EOF
```

```bash
# 키가 존재하지 않을 때만 쓰기 (초기화)
etcdctl txn <<EOF
version("/config/initialized") = "0"

put /config/initialized "true"
put /config/value "default"

get /config/initialized
EOF
```

---

## 출력 포맷

```bash
# 기본 출력 (텍스트)
etcdctl get /myapp/config/env

# JSON 출력
etcdctl get /myapp/config/env --write-out=json | jq .

# 표 형식 (멤버 목록, 엔드포인트 상태에 유용)
etcdctl member list --write-out=table
etcdctl endpoint status --write-out=table
```

---

## 유용한 관리 명령어

```bash
# 클러스터 상태 요약
etcdctl endpoint status --write-out=table

# 헬스 체크
etcdctl endpoint health

# 멤버 목록
etcdctl member list --write-out=table

# 현재 Leader 확인
etcdctl endpoint status --write-out=json | \
  jq '.[] | select(.Status.leader != 0) | .Endpoint'

# 전체 키 수 확인
etcdctl get "" --prefix --keys-only | wc -l

# DB 크기 확인
etcdctl endpoint status --write-out=json | jq '.[0].Status.dbSize'
```

---

## 참고 링크

- [etcdctl 명령어 레퍼런스](https://etcd.io/docs/v3.5/dev-guide/interacting_v3/)
- [etcd Watch API](https://etcd.io/docs/v3.5/learning/api/#watch-api)
- [etcd Lease API](https://etcd.io/docs/v3.5/learning/api/#lease-api)
- [etcd Transaction API](https://etcd.io/docs/v3.5/learning/api/#transaction)
