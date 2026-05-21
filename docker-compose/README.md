# Docker Compose — LLM 모니터링 스택

## 구성 요소

| 서비스          | 이미지                                            | 포트            | 역할 |
| --------------- | -------------------------------------------------- | --------------- | ---- |
| otel-collector  | otel/opentelemetry-collector-contrib:0.111.0       | 4317, 4318      | OTLP 수신 → fan-out |
| prometheus      | prom/prometheus:v2.55.1                            | 9090            | 메트릭 저장 (remote-write 수신) |
| loki            | grafana/loki:3.2.1                                 | 3100            | 로그 저장 (OTLP 네이티브) |
| tempo           | grafana/tempo:2.6.1                                | 3200, 9095      | 트레이스 저장 |
| grafana         | grafana/grafana:11.3.0                             | 3000            | 시각화 |

## 실행

```bash
cp .env.example .env
# .env 안의 비밀번호 채우기
docker compose up -d

# 상태 확인
docker compose ps
docker compose logs -f otel-collector
```

종료:

```bash
docker compose down            # 컨테이너 삭제
docker compose down -v         # 볼륨까지 삭제 (데이터 초기화)
```

## 접속

| URL                       | 비고                                  |
| ------------------------- | ------------------------------------- |
| http://localhost:3000     | Grafana — 기본 admin/admin            |
| http://localhost:4318     | OTLP/HTTP — 에이전트 연결 엔드포인트  |
| localhost:4317            | OTLP/gRPC                             |
| http://localhost:9090     | Prometheus UI                         |
| http://localhost:3100     | Loki API                              |
| http://localhost:3200     | Tempo API                             |

## 데이터 흐름 확인

```bash
# 1) OTel Collector 헬스 체크
curl -s http://localhost:13133/ | jq .

# 2) Prometheus가 수집기 self-metrics를 보고 있는지
curl -s 'http://localhost:9090/api/v1/query?query=up' | jq '.data.result'

# 3) 임의 OTLP 메트릭 한 건 발송 (수집기가 수신/포워딩하는지 빠른 테스트)
curl -X POST http://localhost:4318/v1/metrics \
  -H "Content-Type: application/json" \
  -d '{
    "resourceMetrics":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"smoke-test"}}]},
    "scopeMetrics":[{"metrics":[{"name":"smoke_test_count","sum":{"dataPoints":[{"asInt":"1","timeUnixNano":"'$(date +%s)000000000'"}],"aggregationTemporality":2,"isMonotonic":true}}]}]}]
  }'

# 4) Prometheus에서 확인
sleep 5
curl -s 'http://localhost:9090/api/v1/query?query=smoke_test_count_total' | jq '.data.result'
```

자동화된 검증은 `../scripts/smoke-test.sh` 참조.

## 에이전트 연결

`../agents/` 폴더의 각 가이드를 참조해 도구의 설정 파일을 수정하세요.

| 에이전트       | 가이드                          | 모니터링 방식 / OTLP 엔드포인트       |
| -------------- | ------------------------------- | ------------------------------------- |
| Claude Code    | ../agents/claude-code.md        | 네이티브 OTLP → http://localhost:4318 |
| GitHub Copilot | ../agents/github-copilot.md     | 네이티브 OTLP → http://localhost:4318 |
| OpenClaw       | ../agents/openclaw.md           | 네이티브 OTLP → http://localhost:4318 |
| Codex          | ../agents/codex.md              | 계정 기반 — 제공자 측 사용량 export 필요 |
| Cursor         | ../agents/cursor.md             | 계정 기반 — 제공자 측 사용량 export 필요 |

> Codex/Cursor를 **API 키 기반**으로 쓰는 경우엔 LiteLLM 같은 OpenAI 호환 게이트웨이를
> 중간에 두고 OTLP를 발행할 수 있습니다. 사내가 **계정 로그인 기반**이라면
> LLM 호출이 제공자 서버 측에서 일어나므로 로컬에서는 가로챌 수 없고,
> 각 제공자의 관리 콘솔 export를 사용해야 합니다.

## 문제 해결

**증상**: Grafana에서 메트릭이 안 보임
1. `docker compose logs otel-collector | grep -i error`
2. Prometheus → Status → Targets 에서 `otel-collector-self` UP 확인
3. 에이전트 측 OTLP 엔드포인트가 `http://host.docker.internal:4318` 또는
   호스트 IP인지 확인 (Linux 호스트는 `network_mode: host` 또는 도커 게이트웨이 IP 사용)

**증상**: 로그가 Loki로 안 들어옴
- Loki 3.x 이상이어야 OTLP 수신 가능. `docker compose logs loki | grep otlp`
- `allow_structured_metadata: true` 설정 확인 (loki-config.yaml)
