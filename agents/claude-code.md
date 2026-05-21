# Claude Code 연동

Claude Code는 환경변수 기반으로 OpenTelemetry 신호를 발행합니다.
공식 문서: https://code.claude.com/docs/en/monitoring-usage

## 1) 설정 위치

Claude Code의 `settings.json`은 다음 위치에 있습니다.

- macOS / Linux: `~/.claude/settings.json`
- Windows:       `%USERPROFILE%\.claude\settings.json`
- 프로젝트 단위 오버라이드: 프로젝트 루트의 `.claude/settings.json`

## 2) 추가할 항목

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4318",
    "OTEL_LOG_USER_PROMPTS": "1",
    "OTEL_LOG_TOOL_DETAILS": "1",
    "OTEL_METRICS_INCLUDE_VERSION": "true",
    "OTEL_RESOURCE_ATTRIBUTES": "service.name=claude-code,deployment.environment=local,user.name=jblim,user.email=jblim@example.com,team=platform"
  }
}
```

`OTEL_RESOURCE_ATTRIBUTES` 한 줄에 콤마로 임의 키=값을 나열할 수 있고,
값들은 **모든 메트릭의 라벨**(`user_name`, `user_email`, `team`)과
**Loki 로그의 인덱스 라벨**로 자동 변환됩니다.
(설정 파일 측 `loki-config.yaml`에서 이미 인덱스 라벨로 승격 등록됨)

### 엔드포인트를 어디로?

| 환경                                      | `OTEL_EXPORTER_OTLP_ENDPOINT`              |
| ----------------------------------------- | ------------------------------------------ |
| 로컬 docker-compose                       | `http://localhost:4318`                    |
| K8s + port-forward                        | `http://localhost:4318` (forward 후)       |
| K8s NodePort                              | `http://<node-ip>:30318`                   |
| K8s Ingress                               | `https://otlp.llm-monitoring.example.com`  |

## 3) 사용자 / 팀 라벨 주입 — 상세

`OTEL_RESOURCE_ATTRIBUTES` 는 OpenTelemetry 표준 환경변수로, 콤마로 구분된 키=값
쌍을 *모든* 텔레메트리(메트릭/로그/트레이스)의 resource 속성으로 붙입니다.

### 권장 키 세트

| 키                       | 예시                          | 용도 / 카디널리티 비고                               |
| ------------------------ | ----------------------------- | --------------------------------------------------- |
| `service.name`           | `claude-code`                 | 에이전트 식별 (대시보드의 `agent` 라벨로 정규화됨)  |
| `deployment.environment` | `local` / `prod` / `staging`  | 환경 구분                                            |
| `user.name`              | `jblim`                       | 사번/로그인 ID — Top N 사용자 패널에 사용            |
| `user.email`             | `jblim@example.com`           | (선택) 사람이 알아보기 쉬운 식별자. 카디널리티 주의 |
| `team`                   | `platform`                    | 팀별 합산                                            |
| `org.unit`               | `cloud-infra`                 | (선택) 더 큰 조직 단위                               |

### Prometheus 측 변환 규칙

OTel 속성 이름에 있는 `.` 은 Prometheus 라벨에서 `_` 로 바뀝니다.

```
OTEL_RESOURCE_ATTRIBUTES="user.name=jblim,team=platform"
                                ↓
Prometheus 라벨:    user_name="jblim", team="platform"
Loki 인덱스 라벨:  {user_name="jblim", team="platform"}
```

### Grafana 쿼리 예시

```promql
# 내 토큰 사용량 (지난 24h)
sum(increase(claude_code_token_usage_total{user_name="jblim"}[24h]))

# 팀별 누적 비용
sum by (team) (increase(claude_code_cost_usage_total[7d]))

# 사람별 모델 분포
sum by (user_name, model) (rate(claude_code_token_usage_total[$__rate_interval]))
```

### 카디널리티 주의

Prometheus는 *라벨 조합마다 별도 시계열*을 만듭니다. 다음 상황에서 부담이 커집니다.

- 사용자 수 × 모델 수 × 도구 수 × …  → 폭발할 수 있음
- `user.email` 처럼 도메인까지 포함된 긴 문자열은 저장 효율도 떨어짐

권장:
- 사내 사번(`user.id=E12345`) 같이 **짧고 안정적인 식별자**를 우선
- `user.email`은 추적용으로만 쓰거나 해시(`sha256` 앞 8자리)
- 1000명 이상 규모면 *roll-up recording rule* 을 만들어 대시보드는 집계 시계열을 보게 하기

### 강제 적용 (Project-level)

특정 레포에서만 라벨을 다르게 주려면 프로젝트 루트의 `.claude/settings.json`에
같은 `env` 블록을 두면 됩니다. 사용자 단위 설정을 덮어씁니다.

```json
// <repo>/.claude/settings.json
{
  "env": {
    "OTEL_RESOURCE_ATTRIBUTES": "service.name=claude-code,user.name=jblim,team=platform,project=billing"
  }
}
```

사내 전체에 통일된 라벨 정책을 강제하려면 `agents/team-rollout.md` 참고.

## 4) 민감 콘텐츠 마스킹

- `OTEL_LOG_USER_PROMPTS=1`을 켜면 사용자 프롬프트 본문이 Loki에 들어갑니다.
  사내 규정상 부적절하다면 **둘 다 끄거나** (`OTEL_LOG_USER_PROMPTS`, `OTEL_LOG_TOOL_DETAILS`)
- 수집기 측에서 `attributes/redact-prompts` processor를 활성화하면 해시로 대체됩니다.
  (`docker-compose/configs/otel/otel-collector-config.yaml`의 주석 참조)

## 5) 동작 확인

세션을 한 번 실행한 뒤:

```bash
# Prometheus에서 Claude Code 메트릭 조회
curl -s 'http://localhost:9090/api/v1/query?query=claude_code_session_count_total' | jq

# Loki 직접 조회
curl -s -G 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={service_name="claude-code"}' \
  --data-urlencode "start=$(date -v-1H +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" | jq '.data.result | length'
```

Grafana > "LLM Overview" 대시보드에서 토큰/비용/세션 패널에 값이 나타나야 합니다.
"LLM by User / Team" 대시보드에서 user_name/team 라벨로 필터·그룹 가능합니다.

## 6) 발행되는 주요 메트릭

| OTel 이름                            | Prometheus 변환                       | 의미                       |
| ------------------------------------ | ------------------------------------- | -------------------------- |
| `claude_code.session.count`          | `claude_code_session_count_total`     | 세션 시작 수               |
| `claude_code.token.usage`            | `claude_code_token_usage_total`       | type=input/output/cacheRead/cacheCreation |
| `claude_code.cost.usage`             | `claude_code_cost_usage_total`        | USD 비용                   |
| `claude_code.code_edit_tool.decision`| `claude_code_code_edit_tool_decision_total` | 도구 사용/거부      |
| `claude_code.lines_of_code.count`    | `claude_code_lines_of_code_count_total` | 추가/삭제된 라인 수     |
| `claude_code.api_request`            | `claude_code_api_request_total`       | 모델 API 호출 수           |
| `claude_code.api_error`              | `claude_code_api_error_total`         | 모델 API 오류 수           |

레이블 키는 `model`, `type`, `tool`, `decision`, `agent`(service.name 정규화) 등이 따라옵니다.
