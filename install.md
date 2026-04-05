# Docker로 etcd 설치

---

## 사전 조건 확인

```bash
# Docker 버전 확인
docker version

# Docker Compose 버전 확인
docker compose version
```

---

## 단일 노드 (개발/테스트용)

```bash
# 단일 etcd 노드 실행
docker run -d \
  --name etcd \
  --restart unless-stopped \
  -p 2379:2379 \
  -p 2380:2380 \
  -v etcd-data:/etcd-data \
  quay.io/coreos/etcd:v3.5.17 \
  etcd \
  --name etcd-single \
  --data-dir /etcd-data \
  --advertise-client-urls http://0.0.0.0:2379 \
  --listen-client-urls http://0.0.0.0:2379 \
  --initial-advertise-peer-urls http://0.0.0.0:2380 \
  --listen-peer-urls http://0.0.0.0:2380

# 동작 확인
docker exec etcd etcdctl endpoint health
```

---

## 단일 노드 — Docker Compose

```yaml
# compose-single.yaml
services:
  etcd:
    image: quay.io/coreos/etcd:v3.5.17
    container_name: etcd
    restart: unless-stopped
    ports:
      - "2379:2379"
      - "2380:2380"
    volumes:
      - etcd-data:/etcd-data
    command:
      - etcd
      - --name=etcd-single
      - --data-dir=/etcd-data
      - --advertise-client-urls=http://0.0.0.0:2379
      - --listen-client-urls=http://0.0.0.0:2379
      - --initial-advertise-peer-urls=http://0.0.0.0:2380
      - --listen-peer-urls=http://0.0.0.0:2380

volumes:
  etcd-data:
```

```bash
docker compose -f compose-single.yaml up -d
```

---

## etcdctl 사용법

etcdctl은 etcd 컨테이너에 내장되어 있습니다.

```bash
# 컨테이너 내부에서 실행
docker exec etcd etcdctl put foo bar
docker exec etcd etcdctl get foo

# API 버전 확인 (v3 사용 권장)
docker exec etcd etcdctl version

# 환경 변수로 엔드포인트 지정
docker exec -e ETCDCTL_API=3 etcd etcdctl \
  --endpoints=http://localhost:2379 \
  endpoint health
```

> **API 버전**: etcd v3.4 이후 기본값이 v3이지만, 명시적으로 `ETCDCTL_API=3`을 설정하는 것이 안전합니다.

---

## etcdctl 로컬 설치 (선택)

컨테이너 밖에서 etcdctl을 사용하고 싶은 경우:

```bash
# etcd 바이너리 다운로드 (Linux x86_64)
ETCD_VER=v3.5.17
curl -L https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz \
  -o etcd.tar.gz
tar xzf etcd.tar.gz
sudo mv etcd-${ETCD_VER}-linux-amd64/etcdctl /usr/local/bin/

# 확인
etcdctl version

# 엔드포인트 지정
etcdctl --endpoints=http://localhost:2379 endpoint health
```

---

## 설치 확인

```bash
# 헬스 체크
docker exec etcd etcdctl endpoint health

# 클러스터 정보
docker exec etcd etcdctl endpoint status --write-out=table

# 멤버 목록
docker exec etcd etcdctl member list --write-out=table

# 읽기/쓰기 테스트
docker exec etcd etcdctl put /test/hello "world"
docker exec etcd etcdctl get /test/hello
```

정상 출력 예시:
```
+----------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
|    ENDPOINT    |        ID        | VERSION | DB SIZE | IS LEADER | IS LEARNER | RAFT TERM | RAFT INDEX | RAFT APPLIED INDEX | ERRORS |
+----------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
| 127.0.0.1:2379 | 8e9e05c52164694d |  3.5.17 |   20 kB |      true |      false |         2 |          4 |                  4 |        |
+----------------+------------------+---------+---------+-----------+------------+-----------+------------+--------------------+--------+
```

---

## 삭제

```bash
# 단일 노드 삭제
docker stop etcd && docker rm etcd
docker volume rm etcd-data

# Compose로 실행한 경우
docker compose -f compose-single.yaml down -v
```
