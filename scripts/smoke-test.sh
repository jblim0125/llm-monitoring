#!/usr/bin/env bash
# 엔드포인트가 살아있고 OTLP → Prometheus 흐름이 동작하는지 빠른 검증
set -euo pipefail

ENDPOINT="${OTLP_ENDPOINT:-http://localhost:4318}"
PROM="${PROM_URL:-http://localhost:9090}"
LOKI="${LOKI_URL:-http://localhost:3100}"

echo "[+] Smoke test"
echo "    OTLP   : $ENDPOINT"
echo "    Prom   : $PROM"
echo "    Loki   : $LOKI"
echo

# 1) 메트릭 한 건 OTLP/HTTP로 발사
NOW_NS=$(( $(date +%s) * 1000000000 ))
PAYLOAD=$(cat <<JSON
{
  "resourceMetrics": [{
    "resource": {
      "attributes": [
        {"key":"service.name","value":{"stringValue":"smoke-test"}}
      ]
    },
    "scopeMetrics": [{
      "metrics": [{
        "name": "smoke_test_count",
        "sum": {
          "dataPoints": [{
            "asInt": "1",
            "timeUnixNano": "$NOW_NS"
          }],
          "aggregationTemporality": 2,
          "isMonotonic": true
        }
      }]
    }]
  }]
}
JSON
)

echo "[+] OTLP 메트릭 전송"
HTTP_CODE=$(curl -s -o /tmp/otlp-resp.json -w "%{http_code}" \
  -X POST "$ENDPOINT/v1/metrics" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")
echo "    HTTP $HTTP_CODE  (body: $(cat /tmp/otlp-resp.json))"
if [[ "$HTTP_CODE" != "200" && "$HTTP_CODE" != "202" ]]; then
  echo "[!] 수집기가 OTLP를 받지 못했습니다. 컨테이너 로그를 확인하세요."
  exit 1
fi

# 2) 로그 한 건 OTLP/HTTP로 발사
LOG_PAYLOAD=$(cat <<JSON
{
  "resourceLogs": [{
    "resource": {
      "attributes": [{"key":"service.name","value":{"stringValue":"smoke-test"}}]
    },
    "scopeLogs": [{
      "logRecords": [{
        "timeUnixNano": "$NOW_NS",
        "severityNumber": 9,
        "severityText": "INFO",
        "body": {"stringValue": "smoke test log from $(hostname)"}
      }]
    }]
  }]
}
JSON
)
echo "[+] OTLP 로그 전송"
curl -s -o /dev/null -w "    HTTP %{http_code}\n" \
  -X POST "$ENDPOINT/v1/logs" \
  -H "Content-Type: application/json" \
  -d "$LOG_PAYLOAD"

# 3) Prometheus에서 확인 (수집기 → remote-write → prom 사이 지연 고려)
echo "[+] Prometheus 반영 대기 (최대 30초)"
for i in {1..15}; do
  RESULT=$(curl -fsS "$PROM/api/v1/query?query=smoke_test_count_total" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d['data']['result']))" 2>/dev/null || echo 0)
  if [[ "$RESULT" -gt 0 ]]; then
    echo "    Prometheus에서 smoke_test_count_total 발견 ✅"
    break
  fi
  sleep 2
done
if [[ "$RESULT" -eq 0 ]]; then
  echo "[!] Prometheus에서 메트릭을 찾지 못했습니다. otel-collector / prometheus 로그 확인 필요."
fi

# 4) Loki 확인
echo "[+] Loki 반영 대기 (최대 30초)"
START=$(( ($(date +%s) - 300) * 1000000000 ))
END=$(( $(date +%s) * 1000000000 ))
for i in {1..15}; do
  COUNT=$(curl -s -G "$LOKI/loki/api/v1/query_range" \
    --data-urlencode 'query={service_name="smoke-test"}' \
    --data-urlencode "start=$START" --data-urlencode "end=$END" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(sum(len(r.get('values', [])) for r in d.get('data',{}).get('result',[])))" 2>/dev/null || echo 0)
  if [[ "$COUNT" -gt 0 ]]; then
    echo "    Loki에서 smoke-test 로그 발견 ✅"
    break
  fi
  sleep 2
done
if [[ "$COUNT" -eq 0 ]]; then
  echo "[!] Loki에서 로그를 찾지 못했습니다. otel-collector / loki 로그 확인 필요."
fi

echo
echo "[+] 끝."
