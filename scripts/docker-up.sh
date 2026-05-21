#!/usr/bin/env bash
# docker-compose 스택 기동 + 빠른 헬스체크
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
cd "$ROOT/docker-compose"

if [[ ! -f .env ]]; then
  echo "[+] .env 파일이 없어 .env.example을 복사합니다 (필요 시 수정하세요)."
  cp .env.example .env
fi

echo "[+] docker compose up -d"
docker compose up -d

echo "[+] 서비스 안정화 대기 (최대 60초)..."
for svc in otel-collector prometheus loki tempo grafana; do
  for _ in {1..30}; do
    if docker compose ps "$svc" 2>/dev/null | grep -q "Up"; then
      echo "    - $svc: Up"
      break
    fi
    sleep 2
  done
done

echo
echo "[+] 헬스 체크"
curl -fsS http://localhost:13133 >/dev/null && echo "    - OTel Collector: OK"   || echo "    - OTel Collector: FAIL"
curl -fsS http://localhost:9090/-/ready >/dev/null && echo "    - Prometheus:     OK" || echo "    - Prometheus:     FAIL"
curl -fsS http://localhost:3100/ready >/dev/null && echo "    - Loki:           OK"   || echo "    - Loki:           FAIL"
curl -fsS http://localhost:3200/ready >/dev/null && echo "    - Tempo:          OK"   || echo "    - Tempo:          FAIL"
curl -fsS http://localhost:3000/api/health >/dev/null && echo "    - Grafana:        OK"   || echo "    - Grafana:        FAIL"

cat <<EOF

[+] 완료. 접속:
    - Grafana:    http://localhost:3000  (계정은 .env)
    - OTLP HTTP:  http://localhost:4318
    - OTLP gRPC:  localhost:4317

[+] 에이전트 연결 가이드: ../agents/
EOF
