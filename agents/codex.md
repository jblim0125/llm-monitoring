# Codex (계정 로그인 사용자)

## 결론부터

**계정 로그인 기반 Codex는 본 모니터링 스택과 직접 연동되지 않습니다.**
사용자가 ChatGPT 계정으로 로그인해서 Codex를 쓰는 경우, LLM 호출은
OpenAI 클라우드에서 처리되므로 사용자 로컬 머신을 OTLP로 가로채봐야
의미 있는 데이터가 잡히지 않습니다.

```
사용자(로컬)  ──(OAuth 세션)──>  OpenAI Codex 서버  ──(내부)──>  모델
                                       ▲
                                       └── 사용량은 여기에 기록됨 (로컬에서 안 보임)
```

## 사용 가능한 대안 두 가지

### 1) ChatGPT 워크스페이스의 사용량 export 사용

ChatGPT Business / Enterprise 워크스페이스 관리자는 멤버별 사용량 데이터를
대시보드 또는 CSV/SCIM API로 받을 수 있습니다.

- 워크스페이스 admin → **Compliance** / **Usage** 패널
- 부서/팀별 비용 배분이 필요하면 SCIM/SSO로 그룹 정보를 매핑

이 데이터를 본 스택의 Prometheus/Loki로 흘려보내려면 별도 ETL이 필요합니다.
주기적으로 export를 받아 OTLP로 다시 발행하는 작은 사이드카(예: Python +
`opentelemetry-sdk`)를 사내 cron / K8s CronJob 으로 돌리는 패턴이 일반적입니다.

```
ChatGPT Admin API  ──fetch──>  small ETL job  ──OTLP──>  OTel Collector  ──>  Prometheus
        (매시간)                 (K8s CronJob)
```

### 2) API 키 기반으로 전환(가능한 경우)

만약 일부 팀이 Codex CLI를 **개인 OpenAI API 키**로 쓰는 운영 모드로 전환할 수
있다면, 그 경로는 LiteLLM 같은 OpenAI 호환 게이트웨이로 가로채 OTLP로 발행할 수
있습니다. 본 스택에는 LiteLLM이 포함되어 있지 않으니, 필요하면 별도로 추가하세요.

## 어쨌든 본 스택에서 보고 싶다면 무엇을 해야 하나

1. ChatGPT/OpenAI admin export 자동화 스크립트를 사내에 별도 운영.
2. 그 결과를 OTel SDK로 다음과 같은 메트릭으로 변환해 OTLP/HTTP `:4318`로 push:
   - `codex_tokens_total{user=..., model=..., type=input|output}`
   - `codex_requests_total{user=..., model=..., status=...}`
   - `codex_cost_total{user=..., model=...}`
3. `service.name=codex` 로 resource attribute를 지정하면 Grafana 대시보드의
   "에이전트별" 분석에 자동 포함됩니다.

샘플 export 스크립트는 OpenAI 측 API 문서가 갱신될 때마다 바뀌므로
이 저장소에는 포함하지 않았습니다. 필요해지면 별도로 작성하세요.

## 안 되는 것 (오해 방지)

- 사용자 PC에서 환경변수만 설정해서 Codex 호출을 가로채는 것 — 불가능합니다.
- `mitmproxy`로 Codex 클라이언트의 TLS 트래픽을 디코드 — 인증서 변조가 필요하고
  대부분 클라이언트가 인증서 핀닝을 합니다. 사내 규정상 위험합니다.
- Codex CLI에 `OTEL_*` 환경변수를 주는 것 — 현재 Codex CLI는 이 변수들을 읽지 않습니다.
