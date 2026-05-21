# etcd 설치 가이드

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

---

---

# systemd로 etcd 설치

바이너리를 직접 설치하고 systemd 서비스로 관리하는 방식입니다.
프로덕션 환경에서 VM/베어메탈에 etcd를 배포할 때 권장합니다.

---

## 사전 조건 확인

```bash
# Linux 배포판 확인 (systemd 기반이어야 함)
systemctl --version

# 사용자 및 권한 확인
id
```

---

## 바이너리 설치

```bash
ETCD_VER=v3.5.17
ARCH=linux-amd64   # ARM이면 linux-arm64로 변경

# 다운로드
curl -L https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-${ARCH}.tar.gz \
  -o /tmp/etcd.tar.gz

# 압축 해제 및 설치
tar xzf /tmp/etcd.tar.gz -C /tmp/
sudo mv /tmp/etcd-${ETCD_VER}-${ARCH}/etcd     /usr/local/bin/
sudo mv /tmp/etcd-${ETCD_VER}-${ARCH}/etcdctl  /usr/local/bin/
sudo mv /tmp/etcd-${ETCD_VER}-${ARCH}/etcdutl  /usr/local/bin/

# 설치 확인
etcd --version
etcdctl version
```

---

## 사용자 및 디렉토리 생성

```bash
# etcd 전용 시스템 사용자 생성 (로그인 불가)
sudo useradd --system --no-create-home --shell /sbin/nologin etcd

# 데이터 디렉토리 생성 및 권한 설정
sudo mkdir -p /var/lib/etcd
sudo chown -R etcd:etcd /var/lib/etcd
sudo chmod 700 /var/lib/etcd
```

---

## 환경 설정 파일 작성

```bash
# /etc/etcd/etcd.conf 생성
sudo mkdir -p /etc/etcd
sudo tee /etc/etcd/etcd.conf > /dev/null <<EOF
# 노드 식별
ETCD_NAME=etcd-single
ETCD_DATA_DIR=/var/lib/etcd

# 클라이언트 통신
ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
ETCD_ADVERTISE_CLIENT_URLS=http://127.0.0.1:2379

# 피어 통신
ETCD_LISTEN_PEER_URLS=http://0.0.0.0:2380
ETCD_INITIAL_ADVERTISE_PEER_URLS=http://127.0.0.1:2380

# 클러스터 초기화
ETCD_INITIAL_CLUSTER=etcd-single=http://127.0.0.1:2380
ETCD_INITIAL_CLUSTER_TOKEN=etcd-cluster-token
ETCD_INITIAL_CLUSTER_STATE=new
EOF

sudo chmod 640 /etc/etcd/etcd.conf
sudo chown root:etcd /etc/etcd/etcd.conf
```

---

## systemd 유닛 파일 작성

```bash
sudo tee /etc/systemd/system/etcd.service > /dev/null <<EOF
[Unit]
Description=etcd key-value store
Documentation=https://etcd.io/docs/
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=etcd
Group=etcd
EnvironmentFile=/etc/etcd/etcd.conf
ExecStart=/usr/local/bin/etcd
Restart=on-failure
RestartSec=5s
LimitNOFILE=65536
LimitNPROC=65536

# 보안 강화
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF
```

---

## 서비스 시작

```bash
# systemd 데몬 리로드
sudo systemctl daemon-reload

# 부팅 시 자동 시작 설정
sudo systemctl enable etcd

# 서비스 시작
sudo systemctl start etcd

# 상태 확인
sudo systemctl status etcd
```

---

## 설치 확인

```bash
export ETCDCTL_API=3

# 헬스 체크
etcdctl --endpoints=http://127.0.0.1:2379 endpoint health

# 클러스터 상태
etcdctl --endpoints=http://127.0.0.1:2379 endpoint status --write-out=table

# 읽기/쓰기 테스트
etcdctl --endpoints=http://127.0.0.1:2379 put /test/hello "world"
etcdctl --endpoints=http://127.0.0.1:2379 get /test/hello
```

---

## 로그 확인

```bash
# 실시간 로그
sudo journalctl -u etcd -f

# 최근 100줄
sudo journalctl -u etcd -n 100

# 특정 시간 이후 로그
sudo journalctl -u etcd --since "2026-01-01 00:00:00"
```

---

## 서비스 관리 명령어

```bash
sudo systemctl start   etcd   # 시작
sudo systemctl stop    etcd   # 중지
sudo systemctl restart etcd   # 재시작
sudo systemctl reload  etcd   # 설정 리로드 (지원 시)
sudo systemctl status  etcd   # 상태 확인
sudo systemctl disable etcd   # 자동 시작 해제
```

---

## 삭제

```bash
sudo systemctl stop    etcd
sudo systemctl disable etcd
sudo rm /etc/systemd/system/etcd.service
sudo systemctl daemon-reload

sudo rm -rf /etc/etcd
sudo rm -rf /var/lib/etcd
sudo userdel etcd

sudo rm /usr/local/bin/etcd \
        /usr/local/bin/etcdctl \
        /usr/local/bin/etcdutl
```
