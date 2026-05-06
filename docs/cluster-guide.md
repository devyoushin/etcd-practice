# etcd 클러스터 구성 (3중화 / 5중화)

etcd는 **Raft 합의 알고리즘**으로 동작하므로 클러스터는 반드시 **홀수 노드**로 구성해야 합니다.

---

## 클러스터 크기 선택 기준

```
노드 수  쿼럼(과반수)  허용 장애  용도
  1         1            0       개발/테스트 전용
  3         2            1       운영 기본 (권장 최소)
  5         3            2       운영 고가용성 (권장)
  7         4            3       초대형 환경 (지연 증가 주의)
```

> **짝수 노드 금지**: 4노드 클러스터는 장애 허용이 3노드와 동일(1개)하지만 비용만 증가합니다.
> 쿼럼은 `floor(N/2) + 1` 공식을 따릅니다.

---

## 클러스터 구성 방식

etcd 클러스터를 시작하는 방법은 두 가지입니다:

| 방식 | 설명 | 장점 |
|---|---|---|
| **Static** | 모든 멤버 주소를 시작 시 직접 지정 | 간단, 예측 가능 |
| **Dynamic (etcd Discovery)** | Discovery URL로 자동 구성 | 멤버 주소 미리 몰라도 됨 |

실습에서는 **Static 방식**을 사용합니다.

---

## 3중화 클러스터

### 구성 계획

```
etcd-1: 172.20.0.11:2379 (client), 172.20.0.11:2380 (peer)
etcd-2: 172.20.0.12:2379 (client), 172.20.0.12:2380 (peer)
etcd-3: 172.20.0.13:2379 (client), 172.20.0.13:2380 (peer)

허용 장애: 1개 노드
쿼럼: 2개 이상 정상
```

### Docker Compose로 3중화 클러스터 구성

```yaml
# compose-3node.yaml
networks:
  etcd-net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/24

volumes:
  etcd1-data:
  etcd2-data:
  etcd3-data:

x-etcd-common: &etcd-common
  image: quay.io/coreos/etcd:v3.5.17
  restart: unless-stopped
  networks:
    - etcd-net

services:
  etcd-1:
    <<: *etcd-common
    container_name: etcd-1
    hostname: etcd-1
    volumes:
      - etcd1-data:/etcd-data
    networks:
      etcd-net:
        ipv4_address: 172.20.0.11
    ports:
      - "2379:2379"
    command:
      - etcd
      - --name=etcd-1
      - --data-dir=/etcd-data
      - --listen-client-urls=http://0.0.0.0:2379
      - --advertise-client-urls=http://172.20.0.11:2379
      - --listen-peer-urls=http://0.0.0.0:2380
      - --initial-advertise-peer-urls=http://172.20.0.11:2380
      - --initial-cluster=etcd-1=http://172.20.0.11:2380,etcd-2=http://172.20.0.12:2380,etcd-3=http://172.20.0.13:2380
      - --initial-cluster-state=new
      - --initial-cluster-token=etcd-cluster-token
      - --auto-compaction-retention=1h
      - --snapshot-count=10000

  etcd-2:
    <<: *etcd-common
    container_name: etcd-2
    hostname: etcd-2
    volumes:
      - etcd2-data:/etcd-data
    networks:
      etcd-net:
        ipv4_address: 172.20.0.12
    ports:
      - "2380:2379"
    command:
      - etcd
      - --name=etcd-2
      - --data-dir=/etcd-data
      - --listen-client-urls=http://0.0.0.0:2379
      - --advertise-client-urls=http://172.20.0.12:2379
      - --listen-peer-urls=http://0.0.0.0:2380
      - --initial-advertise-peer-urls=http://172.20.0.12:2380
      - --initial-cluster=etcd-1=http://172.20.0.11:2380,etcd-2=http://172.20.0.12:2380,etcd-3=http://172.20.0.13:2380
      - --initial-cluster-state=new
      - --initial-cluster-token=etcd-cluster-token
      - --auto-compaction-retention=1h
      - --snapshot-count=10000

  etcd-3:
    <<: *etcd-common
    container_name: etcd-3
    hostname: etcd-3
    volumes:
      - etcd3-data:/etcd-data
    networks:
      etcd-net:
        ipv4_address: 172.20.0.13
    ports:
      - "2381:2379"
    command:
      - etcd
      - --name=etcd-3
      - --data-dir=/etcd-data
      - --listen-client-urls=http://0.0.0.0:2379
      - --advertise-client-urls=http://172.20.0.13:2379
      - --listen-peer-urls=http://0.0.0.0:2380
      - --initial-advertise-peer-urls=http://172.20.0.13:2380
      - --initial-cluster=etcd-1=http://172.20.0.11:2380,etcd-2=http://172.20.0.12:2380,etcd-3=http://172.20.0.13:2380
      - --initial-cluster-state=new
      - --initial-cluster-token=etcd-cluster-token
      - --auto-compaction-retention=1h
      - --snapshot-count=10000
```

```bash
# 3중화 클러스터 시작
docker compose -f compose-3node.yaml up -d

# 클러스터 상태 확인
docker exec etcd-1 etcdctl \
  --endpoints=http://172.20.0.11:2379,http://172.20.0.12:2379,http://172.20.0.13:2379 \
  endpoint status --write-out=table

# 멤버 목록 확인
docker exec etcd-1 etcdctl \
  --endpoints=http://172.20.0.11:2379 \
  member list --write-out=table
```

정상 출력:
```
+------------------+---------+--------+----------------------------+----------------------------+------------+
|        ID        | STATUS  |  NAME  |         PEER ADDRS         |        CLIENT ADDRS        | IS LEARNER |
+------------------+---------+--------+----------------------------+----------------------------+------------+
| 1a2b3c4d5e6f7a8b | started | etcd-1 | http://172.20.0.11:2380    | http://172.20.0.11:2379    |      false |
| 2b3c4d5e6f7a8b9c | started | etcd-2 | http://172.20.0.12:2380    | http://172.20.0.12:2379    |      false |
| 3c4d5e6f7a8b9c0d | started | etcd-3 | http://172.20.0.13:2380    | http://172.20.0.13:2379    |      false |
+------------------+---------+--------+----------------------------+----------------------------+------------+
```

---

### 3중화 동작 검증

```bash
# 편의를 위한 alias
ENDPOINTS="http://172.20.0.11:2379,http://172.20.0.12:2379,http://172.20.0.13:2379"
alias e3ctl="docker exec etcd-1 etcdctl --endpoints=$ENDPOINTS"

# 쓰기 테스트
e3ctl put /cluster/test "hello from cluster"
e3ctl get /cluster/test

# 현재 Leader 확인
e3ctl endpoint status --write-out=json | jq '.[] | {endpoint: .Endpoint, isLeader: .Status.leader}'

# etcd-1 (Leader일 경우) 중단 → 자동 Leader 재선출 확인
docker stop etcd-1

# etcd-2, etcd-3은 계속 동작 (쿼럼: 2/3)
docker exec etcd-2 etcdctl \
  --endpoints=http://172.20.0.12:2379,http://172.20.0.13:2379 \
  endpoint status --write-out=table

# 쓰기/읽기 계속 동작 확인
docker exec etcd-2 etcdctl \
  --endpoints=http://172.20.0.12:2379,http://172.20.0.13:2379 \
  put /cluster/test2 "still working"

# etcd-1 복구 → 자동으로 클러스터에 재참여
docker start etcd-1
```

---

## 5중화 클러스터

### 구성 계획

```
etcd-1: 172.20.0.11  etcd-2: 172.20.0.12  etcd-3: 172.20.0.13
etcd-4: 172.20.0.14  etcd-5: 172.20.0.15

허용 장애: 2개 노드
쿼럼: 3개 이상 정상
```

### Docker Compose로 5중화 클러스터 구성

```yaml
# compose-5node.yaml
networks:
  etcd-net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/24

volumes:
  etcd1-data:
  etcd2-data:
  etcd3-data:
  etcd4-data:
  etcd5-data:

x-etcd-common: &etcd-common
  image: quay.io/coreos/etcd:v3.5.17
  restart: unless-stopped
  networks:
    - etcd-net

# 공통 클러스터 설정
x-initial-cluster: &initial-cluster
  etcd-1=http://172.20.0.11:2380,etcd-2=http://172.20.0.12:2380,etcd-3=http://172.20.0.13:2380,etcd-4=http://172.20.0.14:2380,etcd-5=http://172.20.0.15:2380

services:
  etcd-1:
    <<: *etcd-common
    container_name: etcd-1
    volumes:
      - etcd1-data:/etcd-data
    networks:
      etcd-net:
        ipv4_address: 172.20.0.11
    ports:
      - "2379:2379"
    command:
      - etcd
      - --name=etcd-1
      - --data-dir=/etcd-data
      - --listen-client-urls=http://0.0.0.0:2379
      - --advertise-client-urls=http://172.20.0.11:2379
      - --listen-peer-urls=http://0.0.0.0:2380
      - --initial-advertise-peer-urls=http://172.20.0.11:2380
      - --initial-cluster=etcd-1=http://172.20.0.11:2380,etcd-2=http://172.20.0.12:2380,etcd-3=http://172.20.0.13:2380,etcd-4=http://172.20.0.14:2380,etcd-5=http://172.20.0.15:2380
      - --initial-cluster-state=new
      - --initial-cluster-token=etcd-cluster-token
      - --auto-compaction-retention=1h

  etcd-2:
    <<: *etcd-common
    container_name: etcd-2
    volumes:
      - etcd2-data:/etcd-data
    networks:
      etcd-net:
        ipv4_address: 172.20.0.12
    ports:
      - "2380:2379"
    command:
      - etcd
      - --name=etcd-2
      - --data-dir=/etcd-data
      - --listen-client-urls=http://0.0.0.0:2379
      - --advertise-client-urls=http://172.20.0.12:2379
      - --listen-peer-urls=http://0.0.0.0:2380
      - --initial-advertise-peer-urls=http://172.20.0.12:2380
      - --initial-cluster=etcd-1=http://172.20.0.11:2380,etcd-2=http://172.20.0.12:2380,etcd-3=http://172.20.0.13:2380,etcd-4=http://172.20.0.14:2380,etcd-5=http://172.20.0.15:2380
      - --initial-cluster-state=new
      - --initial-cluster-token=etcd-cluster-token
      - --auto-compaction-retention=1h

  etcd-3:
    <<: *etcd-common
    container_name: etcd-3
    volumes:
      - etcd3-data:/etcd-data
    networks:
      etcd-net:
        ipv4_address: 172.20.0.13
    ports:
      - "2381:2379"
    command:
      - etcd
      - --name=etcd-3
      - --data-dir=/etcd-data
      - --listen-client-urls=http://0.0.0.0:2379
      - --advertise-client-urls=http://172.20.0.13:2379
      - --listen-peer-urls=http://0.0.0.0:2380
      - --initial-advertise-peer-urls=http://172.20.0.13:2380
      - --initial-cluster=etcd-1=http://172.20.0.11:2380,etcd-2=http://172.20.0.12:2380,etcd-3=http://172.20.0.13:2380,etcd-4=http://172.20.0.14:2380,etcd-5=http://172.20.0.15:2380
      - --initial-cluster-state=new
      - --initial-cluster-token=etcd-cluster-token
      - --auto-compaction-retention=1h

  etcd-4:
    <<: *etcd-common
    container_name: etcd-4
    volumes:
      - etcd4-data:/etcd-data
    networks:
      etcd-net:
        ipv4_address: 172.20.0.14
    ports:
      - "2382:2379"
    command:
      - etcd
      - --name=etcd-4
      - --data-dir=/etcd-data
      - --listen-client-urls=http://0.0.0.0:2379
      - --advertise-client-urls=http://172.20.0.14:2379
      - --listen-peer-urls=http://0.0.0.0:2380
      - --initial-advertise-peer-urls=http://172.20.0.14:2380
      - --initial-cluster=etcd-1=http://172.20.0.11:2380,etcd-2=http://172.20.0.12:2380,etcd-3=http://172.20.0.13:2380,etcd-4=http://172.20.0.14:2380,etcd-5=http://172.20.0.15:2380
      - --initial-cluster-state=new
      - --initial-cluster-token=etcd-cluster-token
      - --auto-compaction-retention=1h

  etcd-5:
    <<: *etcd-common
    container_name: etcd-5
    volumes:
      - etcd5-data:/etcd-data
    networks:
      etcd-net:
        ipv4_address: 172.20.0.15
    ports:
      - "2383:2379"
    command:
      - etcd
      - --name=etcd-5
      - --data-dir=/etcd-data
      - --listen-client-urls=http://0.0.0.0:2379
      - --advertise-client-urls=http://172.20.0.15:2379
      - --listen-peer-urls=http://0.0.0.0:2380
      - --initial-advertise-peer-urls=http://172.20.0.15:2380
      - --initial-cluster=etcd-1=http://172.20.0.11:2380,etcd-2=http://172.20.0.12:2380,etcd-3=http://172.20.0.13:2380,etcd-4=http://172.20.0.14:2380,etcd-5=http://172.20.0.15:2380
      - --initial-cluster-state=new
      - --initial-cluster-token=etcd-cluster-token
      - --auto-compaction-retention=1h
```

```bash
# 5중화 클러스터 시작
docker compose -f compose-5node.yaml up -d

# 전체 엔드포인트 상태 확인
ENDPOINTS_5="http://172.20.0.11:2379,http://172.20.0.12:2379,http://172.20.0.13:2379,http://172.20.0.14:2379,http://172.20.0.15:2379"
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS_5 \
  endpoint status --write-out=table
```

---

### 5중화 장애 허용 검증

```bash
ENDPOINTS_5="http://172.20.0.11:2379,http://172.20.0.12:2379,http://172.20.0.13:2379,http://172.20.0.14:2379,http://172.20.0.15:2379"

# 초기 데이터 저장
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS_5 \
  put /ha-test "5node cluster"

# === 시나리오 1: 2개 노드 동시 장애 ===
docker stop etcd-4 etcd-5
# 3개 노드 남음 (쿼럼 3/5 충족 → 계속 동작)

ENDPOINTS_3="http://172.20.0.11:2379,http://172.20.0.12:2379,http://172.20.0.13:2379"
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS_3 \
  get /ha-test   # 정상 응답

# === 시나리오 2: 3개 노드 장애 (쿼럼 붕괴) ===
docker stop etcd-3
# 2개 노드 남음 (쿼럼 미달 → 쓰기 거부)

ENDPOINTS_2="http://172.20.0.11:2379,http://172.20.0.12:2379"
docker exec etcd-1 etcdctl \
  --endpoints=$ENDPOINTS_2 \
  put /ha-test "this will fail"
# Error: etcdserver: request timed out (Leader 없음)

# === 복구 ===
docker start etcd-3 etcd-4 etcd-5
# 자동으로 클러스터 재합류 및 데이터 동기화
```

---

## 주요 시작 파라미터 설명

| 파라미터 | 설명 |
|---|---|
| `--name` | 이 노드의 이름 (클러스터 내 고유해야 함) |
| `--data-dir` | 데이터 저장 경로 (WAL + 스냅샷) |
| `--listen-client-urls` | 클라이언트 요청 수신 주소 |
| `--advertise-client-urls` | 다른 멤버에게 알릴 클라이언트 주소 |
| `--listen-peer-urls` | 피어(다른 etcd) 요청 수신 주소 |
| `--initial-advertise-peer-urls` | 다른 멤버에게 알릴 피어 주소 |
| `--initial-cluster` | 클러스터 전체 멤버 목록 (이름=피어URL 형식) |
| `--initial-cluster-state` | `new` (최초 구성) 또는 `existing` (기존 클러스터에 참여) |
| `--initial-cluster-token` | 클러스터 식별 토큰 (다른 클러스터와 구분) |
| `--auto-compaction-retention` | 자동 컴팩션 보존 기간 (예: `1h`) |
| `--snapshot-count` | 스냅샷 생성 기준 로그 수 (기본: 100000) |

---

## 다중 서버 환경 (실제 운영)

단일 호스트 Docker Compose는 실습용입니다. 실제 운영에서는 **별도 서버 3대 또는 5대**에 etcd를 배포합니다.

```
서버 1 (IP: 10.0.1.10)  → etcd 컨테이너 또는 바이너리
서버 2 (IP: 10.0.1.11)  → etcd 컨테이너 또는 바이너리
서버 3 (IP: 10.0.1.12)  → etcd 컨테이너 또는 바이너리
```

각 서버에서 Docker로 실행:

```bash
# 서버 1에서 실행
docker run -d \
  --name etcd \
  --restart unless-stopped \
  -p 2379:2379 -p 2380:2380 \
  -v /data/etcd:/etcd-data \
  quay.io/coreos/etcd:v3.5.17 \
  etcd \
  --name=etcd-1 \
  --data-dir=/etcd-data \
  --listen-client-urls=http://0.0.0.0:2379 \
  --advertise-client-urls=http://10.0.1.10:2379 \
  --listen-peer-urls=http://0.0.0.0:2380 \
  --initial-advertise-peer-urls=http://10.0.1.10:2380 \
  --initial-cluster=etcd-1=http://10.0.1.10:2380,etcd-2=http://10.0.1.11:2380,etcd-3=http://10.0.1.12:2380 \
  --initial-cluster-state=new \
  --initial-cluster-token=prod-cluster
```

---

## 참고 링크

- [etcd 클러스터링 공식 문서](https://etcd.io/docs/v3.5/op-guide/clustering/)
- [etcd 운영 가이드](https://etcd.io/docs/v3.5/op-guide/)
- [Raft 리더 선출 시각화](https://raft.github.io/)
