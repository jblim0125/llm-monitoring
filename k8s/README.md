# Kubernetes — LLM 모니터링 스택

원시 YAML manifest로 구성한 사내 K8s 배포본입니다.
Helm/Kustomize 없이 `kubectl apply` 만으로 동작합니다.

## 매니페스트 순서

| 파일                       | 내용                                                |
| -------------------------- | --------------------------------------------------- |
| 00-namespace.yaml          | `llm-monitoring` 네임스페이스                        |
| 10-prometheus.yaml         | Prometheus (remote-write 수신 모드) + PVC           |
| 20-loki.yaml               | Loki 3.x (OTLP 네이티브) + PVC                       |
| 30-tempo.yaml              | Tempo + PVC (트레이스 + metrics generator)          |
| 40-otel-collector.yaml     | OTel Collector Deployment + ClusterIP + NodePort    |
| 50-grafana.yaml            | Grafana + 데이터소스/대시보드 프로비저닝 + NodePort |

## 배포

```bash
# 1) 한 번에 적용
kubectl apply -f 00-namespace.yaml
kubectl apply -f .

# 또는 스크립트 사용 (대시보드 ConfigMap 자동 생성 포함)
../scripts/k8s-apply.sh
```

대시보드 ConfigMap은 `50-grafana.yaml` 안에 placeholder만 있으니
실제 JSON을 넣으려면 다음 명령으로 덮어씁니다(또는 `k8s-apply.sh`가 자동 수행).

```bash
kubectl -n llm-monitoring create configmap grafana-dashboards \
  --from-file=../docker-compose/configs/grafana/dashboards/ \
  --dry-run=client -o yaml | kubectl apply -f -

# Grafana 재시작 (ConfigMap 변경 반영)
kubectl -n llm-monitoring rollout restart deployment/grafana
```

## 접속

기본은 ClusterIP. 로컬 PC에서 사용하려면 port-forward 또는 NodePort 사용.

### A) port-forward (개인 개발자)

```bash
# Grafana
kubectl -n llm-monitoring port-forward svc/grafana 3000:3000
# OTLP 엔드포인트 (에이전트에서 직접 연결)
kubectl -n llm-monitoring port-forward svc/otel-collector 4318:4318 4317:4317
```

→ 에이전트는 `http://localhost:4318` 사용.

### B) NodePort (사내 공용)

| 서비스         | NodePort                   | URL 예                            |
| -------------- | -------------------------- | --------------------------------- |
| grafana        | 30300                      | http://&lt;node-ip&gt;:30300       |
| otel-collector | 30318 (HTTP), 30317 (gRPC) | OTLP 엔드포인트                    |

### C) Ingress (운영)

사내 인그레스 컨트롤러가 있다면 다음 패턴으로 노출:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  namespace: llm-monitoring
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: 50m
spec:
  ingressClassName: nginx
  rules:
    - host: grafana.llm-monitoring.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: grafana
                port: { number: 3000 }
```

OTel Collector를 외부에 노출할 때는 gRPC도 받을 수 있는
인그레스(NGINX의 `nginx.ingress.kubernetes.io/backend-protocol: GRPC` 등)가 필요합니다.

## 시크릿 운영

기본 매니페스트에 들어 있는 자격증명은 PoC용입니다. 운영에서는:

```bash
# Grafana 관리자 비밀번호
kubectl -n llm-monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password='<강력한 비밀번호>' \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n llm-monitoring rollout restart deployment/grafana
```

External Secrets Operator / Sealed Secrets / HashiCorp Vault Agent 등을
이미 쓰고 있다면 그쪽으로 옮기는 것을 권장합니다.

## 스토리지

각 컴포넌트는 PVC를 사용합니다 (Prometheus 20Gi, Loki 20Gi, Tempo 20Gi, Grafana 5Gi).
기본 StorageClass가 없는 클러스터에서는 PVC가 Pending에 멈춥니다 — `kubectl get sc`로 확인하세요.
StorageClass를 지정하려면 각 매니페스트의 PVC 섹션에 `storageClassName:` 을 추가합니다.

## 정리

```bash
kubectl delete -f .
# 또는
kubectl delete namespace llm-monitoring
```
