# Cursor (계정 로그인 사용자)

## 결론부터

**계정 로그인 기반 Cursor는 본 모니터링 스택과 직접 연동되지 않습니다.**
사용자가 Cursor 계정(예: Cursor Pro / Business)으로 로그인해 모델을 사용하는 경우,
LLM 호출은 Cursor 서버에서 처리되므로 사용자 로컬 머신을 OTLP로 가로채봐야
의미 있는 데이터가 잡히지 않습니다.

```
사용자(로컬 Cursor 앱) ──(OAuth 세션)──>  Cursor 서버  ──>  OpenAI/Anthropic/Google
                                              ▲
                                              └── 사용량은 여기에 기록됨 (로컬에서 안 보임)
```

## 사용 가능한 대안 두 가지

### 1) Cursor Business / Teams 관리자 대시보드 사용

Cursor Business / Teams 플랜의 워크스페이스 관리자는 멤버별 사용량/모델별 분포를
대시보드에서 볼 수 있고, 일부 export API를 제공합니다.

- Cursor 워크스페이스 admin 페이지 → **Usage** / **Members**
- SSO/SCIM이 연결되어 있다면 부서/팀 라벨로 집계 가능

이 데이터를 본 스택의 Prometheus/Loki로 옮기려면 별도 ETL이 필요합니다.
주기적으로 export를 받아 OTLP로 다시 발행하는 작은 사이드카(예: Python +
`opentelemetry-sdk`)를 사내 cron / K8s CronJob 으로 돌리는 패턴이 일반적입니다.

```
Cursor Admin export  ──fetch──>  small ETL job  ──OTLP──>  OTel Collector  ──>  Prometheus
       (매시간/매일)               (K8s CronJob)
```

### 2) API 키 기반으로 전환(가능한 경우)

Cursor는 "Use my own API key" 모드를 지원합니다. 그 모드에서는 사용자가 입력한
OpenAI/Anthropic API 키로 호출이 나가므로, OpenAI 호환 게이트웨이(예: LiteLLM)를
중간에 두고 가로챌 수 있습니다. 다만 사내 정책이 **계정 기반**이라면 사용자에게
별도 API 키 사용을 강제하기 어렵습니다.

## 어쨌든 본 스택에서 보고 싶다면 무엇을 해야 하나

1. Cursor admin export 자동화 스크립트를 사내에 별도 운영.
2. 그 결과를 OTel SDK로 다음과 같은 메트릭으로 변환해 OTLP/HTTP `:4318`로 push:
   - `cursor_tokens_total{user=..., model=..., type=input|output}`
   - `cursor_requests_total{user=..., model=...}`
   - `cursor_cost_total{user=..., model=...}`
3. `service.name=cursor` 로 resource attribute를 지정하면 Grafana 대시보드의
   "에이전트별" 분석에 자동 포함됩니다.

샘플 export 스크립트는 Cursor 측 API가 자주 변경되므로 본 저장소에 고정해
두지 않았습니다. 필요해지면 별도로 작성하세요.

## 안 되는 것 (오해 방지)

- Cursor에 환경변수(`OTEL_*`)를 주입해서 OTLP를 발행 — 현재 Cursor는 이 변수들을 읽지 않습니다.
- 사용자 PC에서 Cursor의 HTTPS 트래픽을 mitmproxy로 디코드 — 인증서 핀닝 및 사내 규정 위험.
- `Override OpenAI Base URL`을 켜서 가로채는 방식 — 이는 **API 키 모드**에서만 유효합니다.
  계정 로그인 모드에서는 이 설정이 무시되거나 일부 기능에만 적용됩니다.
