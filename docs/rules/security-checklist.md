# 보안 체크리스트 — etcd-practice

## TLS 보안
- [ ] peer-to-peer TLS 암호화 활성화
- [ ] client-to-server TLS 암호화 활성화
- [ ] 인증서 만료 모니터링 (90일 전 갱신)
- [ ] 클라이언트 인증서 검증 활성화

## 접근 제어
- [ ] 2379 포트: 신뢰할 수 있는 클라이언트만 허용
- [ ] 2380 포트: 피어 노드만 허용 (외부 노출 금지)
- [ ] etcd 인증 활성화 (`etcdctl auth enable`)

## 데이터 보안
- [ ] 데이터 디렉토리 SSD 마운트 (fsync 성능)
- [ ] 데이터 디렉토리 권한: `0700` (etcd 사용자만)
- [ ] 스냅샷 파일 외부 저장소(S3) 암호화 보관

## 클러스터 보안
- [ ] `--initial-cluster-token` 고유 토큰 사용
- [ ] 불필요한 멤버 즉시 제거 (`etcdctl member remove`)
- [ ] 정기 키 로테이션

## 모니터링
- [ ] DB 크기 알람 (`quota-backend-bytes` 80% 도달 시)
- [ ] 리더 변경 알람
- [ ] 높은 fsync 레이턴시 알람 (> 10ms)
