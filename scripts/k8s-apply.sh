#!/usr/bin/env bash
# K8s 매니페스트 적용 + 대시보드 ConfigMap을 실제 JSON으로 채우기
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

NS="llm-monitoring"

echo "[+] 네임스페이스 생성"
kubectl apply -f "$ROOT/k8s/00-namespace.yaml"

echo "[+] 인프라(저장소) 먼저 적용"
kubectl apply -f "$ROOT/k8s/10-prometheus.yaml"
kubectl apply -f "$ROOT/k8s/20-loki.yaml"
kubectl apply -f "$ROOT/k8s/30-tempo.yaml"

echo "[+] OTel Collector"
kubectl apply -f "$ROOT/k8s/40-otel-collector.yaml"

echo "[+] Grafana (placeholder 대시보드 포함)"
kubectl apply -f "$ROOT/k8s/50-grafana.yaml"

echo "[+] 실제 대시보드 JSON을 ConfigMap으로 교체"
kubectl -n "$NS" create configmap grafana-dashboards \
  --from-file="$ROOT/docker-compose/configs/grafana/dashboards/" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[+] Grafana 재시작 (ConfigMap 변경 반영)"
kubectl -n "$NS" rollout restart deployment/grafana

echo "[+] Pod 상태 대기 (최대 3분)"
kubectl -n "$NS" wait --for=condition=Available --timeout=180s deployment --all || true

kubectl -n "$NS" get pods
kubectl -n "$NS" get svc

cat <<EOF

[+] 적용 완료.
    Grafana :  kubectl -n $NS port-forward svc/grafana 3000:3000
    OTLP    :  kubectl -n $NS port-forward svc/otel-collector 4318:4318 4317:4317

NodePort 사용 시 (사내 공용):
    Grafana:   http://<node-ip>:30300
    OTLP HTTP: http://<node-ip>:30318

에이전트 연결 가이드:  $ROOT/agents/
EOF
