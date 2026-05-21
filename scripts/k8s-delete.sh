#!/usr/bin/env bash
# K8s 리소스 정리
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

NS="llm-monitoring"

PURGE="${1:-}"
if [[ "$PURGE" == "--purge" ]]; then
  echo "[!] 네임스페이스 전체 삭제 (PVC/시크릿 포함 — 데이터 손실)"
  kubectl delete namespace "$NS" --wait=false
  exit 0
fi

echo "[+] 매니페스트 단위 삭제 (PVC는 유지 — 데이터 보존)"
kubectl delete -f "$ROOT/k8s/50-grafana.yaml" --ignore-not-found
kubectl delete -f "$ROOT/k8s/40-otel-collector.yaml" --ignore-not-found
kubectl delete -f "$ROOT/k8s/30-tempo.yaml" --ignore-not-found
kubectl delete -f "$ROOT/k8s/20-loki.yaml" --ignore-not-found
kubectl delete -f "$ROOT/k8s/10-prometheus.yaml" --ignore-not-found

echo "[+] 데이터까지 지우려면:  $0 --purge"
