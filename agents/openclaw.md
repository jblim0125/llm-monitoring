# OpenClaw 연동

OpenClaw 게이트웨이는 자체 telemetry 설정 블록을 통해 OTel 신호를 내보냅니다.
공식 문서: https://docs.openclaw.ai/logging#export-to-opentelemetry

## 1) 게이트웨이 설정에 추가

OpenClaw 게이트웨이의 설정 파일(`config.json` 또는 `openclaw.yaml`)
의 telemetry 섹션을 다음과 같이 추가/수정합니다.

```json
{
  "telemetry": {
    "enabled": true,
    "endpoint": "http://localhost:4318",
    "protocol": "http/protobuf",
    "serviceName": "openclaw-gateway",
    "traces": true,
    "metrics": true,
    "logs": true,
    "sampleRate": 1,
    "flushIntervalMs": 5000
  }
}
```

> **중요**: `serviceName`은 반드시 `openclaw-gateway`여야 합니다.
> 대시보드와 데이터소스의 derivedFields가 이 값을 기준으로 필터링합니다.

게이트웨이를 재시작하면 즉시 데이터가 수집기로 흘러갑니다.

## 2) 발행되는 신호

- 메시지 수 (채널별)
- 고유 채팅 수
- 응답 시간 백분위수
- LLM 호출 횟수 / 모델별 분포
- 토큰 사용량 (입력 / 출력 / 캐시 읽기)
- 중단된 세션 수

## 3) 확인 KQL → PromQL 매핑

원본 가이드는 KQL(Application Insights)을 썼습니다. 자체 호스팅에서는:

```promql
# OpenClaw에서 발생한 모든 신호의 RPS
sum(rate({service_name="openclaw-gateway"}[5m]))

# 1시간 메시지
sum(increase(openclaw_messages_total[1h]))

# 모델별 토큰
sum by (model) (rate(openclaw_tokens_total[5m]))
```

Loki:

```logql
{service_name="openclaw-gateway"} |= "error"
{service_name="openclaw-gateway"} |~ "session.*aborted"
```

## 4) 컨테이너로 OpenClaw 자체를 사내에서 같이 운영하는 경우

같은 docker-compose / 같은 K8s 네임스페이스에 OpenClaw를 배치한다면
`endpoint`를 컨테이너 네트워크 이름으로 직접 가리킬 수 있습니다.

```yaml
# docker-compose 추가 예
services:
  openclaw:
    image: openclaw/gateway:latest
    environment:
      OPENCLAW_TELEMETRY_ENDPOINT: http://otel-collector:4318
      OPENCLAW_TELEMETRY_SERVICE_NAME: openclaw-gateway
    networks: [obs]
```

```yaml
# K8s 추가 예 (env 일부만 발췌)
env:
  - name: OPENCLAW_TELEMETRY_ENDPOINT
    value: http://otel-collector.llm-monitoring.svc.cluster.local:4318
  - name: OPENCLAW_TELEMETRY_SERVICE_NAME
    value: openclaw-gateway
```
