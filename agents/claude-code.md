# Claude Code 연동

Claude Code는 환경변수 기반으로 OpenTelemetry 신호(메트릭 / 로그-이벤트 / 트레이스)를
발행합니다. 공식 문서: <https://code.claude.com/docs/ko/monitoring-usage>

## 1) 설정 위치

Claude Code의 `settings.json`은 다음 위치에서 읽힙니다 (아래로 갈수록 우선순위 ↑).

- macOS / Linux: `~/.claude/settings.json`
- Windows: `%USERPROFILE%\.claude\settings.json`
- 프로젝트 단위 오버라이드: 프로젝트 루트의 `.claude/settings.json`
- 관리자 정책(우선순위 최상): MDM 등으로 배포된 관리 설정 파일 — 사용자가 덮어쓸 수 없음

## 2) 추가할 항목

가장 흔한 구성 (OTLP/HTTP + Prometheus 호환):

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4318",
    "OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE": "cumulative",
    "OTEL_LOG_USER_PROMPTS": "1",
    "OTEL_LOG_TOOL_DETAILS": "1",
    "OTEL_METRICS_INCLUDE_VERSION": "true",
    "OTEL_RESOURCE_ATTRIBUTES": "service.name=claude-code,deployment.environment=local,user.name=jblim,user.email=jblim@example.com,team=platform"
  }
}
```

핵심 키 해설:

- `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=cumulative`
  - Claude Code 기본은 `delta`. Prometheus의 remote-write 및 OTLP-write 리시버는
    `cumulative`만 안전하게 처리하므로 Prom 백엔드에선 **필수**.
- `OTEL_LOG_USER_PROMPTS=1`, `OTEL_LOG_TOOL_DETAILS=1`
  - 둘 다 기본 off. 켜야 사용자 프롬프트 본문, Bash 명령 전문, 도구 입력 인자 등이
    Loki 이벤트에 들어옴. 규제 환경에선 끄거나 collector 측에서 마스킹.
- `OTEL_METRICS_INCLUDE_VERSION=true`
  - `app.version` 라벨이 추가됨 (기본 false). 버전별 변동 추적이 필요할 때만 활성화 —
    카디널리티가 한 단계 올라감.

### 트레이스(베타)도 받고 싶다면

```json
"env": {
  "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
  "CLAUDE_CODE_ENHANCED_TELEMETRY_BETA": "1",
  "OTEL_TRACES_EXPORTER": "otlp",
  "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
  "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4318"
}
```

`CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1` 없이는 트레이스 스팬이 전혀 안 나갑니다.
스팬 트리: `claude_code.interaction → llm_request | tool (blocked_on_user, execution) | hook`.

### 엔드포인트를 어디로?

| 환경                          | `OTEL_EXPORTER_OTLP_ENDPOINT`             |
| ----------------------------- | ----------------------------------------- |
| 로컬 docker-compose           | `http://localhost:4318`                   |
| 포트 충돌로 외부 노출 변경 시 | `http://<host>:14318` 등 매핑한 포트 사용 |
| K8s + port-forward            | `http://localhost:4318` (forward 후)      |
| K8s NodePort                  | `http://<node-ip>:30318`                  |
| K8s Ingress                   | `https://otlp.llm-monitoring.example.com` |

`OTEL_EXPORTER_OTLP_ENDPOINT`에는 **base URL만** 넣습니다.
`/v1/metrics`, `/v1/logs`, `/v1/traces` 경로는 SDK가 자동 부가합니다.

### 인증

- 정적 토큰: `OTEL_EXPORTER_OTLP_HEADERS="Authorization=Bearer <token>"`
- 동적 토큰: `settings.json`의 `otelHeadersHelper`에 스크립트 경로 지정.
  스크립트는 헤더를 JSON으로 stdout 출력. 기본 29분마다 재실행
  (`CLAUDE_CODE_OTEL_HEADERS_HELPER_DEBOUNCE_MS`로 조정).
- mTLS: `http/protobuf`는 `CLAUDE_CODE_CLIENT_CERT`/`_KEY`, gRPC는
  `OTEL_EXPORTER_OTLP_CLIENT_CERTIFICATE`/`_CLIENT_KEY` 사용.

## 3) 사용자 / 팀 라벨 주입 — 상세

`OTEL_RESOURCE_ATTRIBUTES`는 OTel 표준 환경변수로, 콤마로 구분된 키=값을 *모든* 신호
(메트릭/로그/트레이스)의 resource attribute로 부착합니다.

### 권장 키 세트

| 키                       | 예시                         | 용도 / 카디널리티 비고                              |
| ------------------------ | ---------------------------- | --------------------------------------------------- |
| `service.name`           | `claude-code`                | 에이전트 식별. Prom 라벨 `service_name`으로 들어옴  |
| `deployment.environment` | `local` / `prod` / `staging` | 환경 구분                                           |
| `user.name`              | `jblim`                      | 사번/로그인 ID — Top N 사용자 패널에 사용           |
| `user.email`             | `jblim@example.com`          | (선택) 사람이 알아보기 쉬운 식별자. 카디널리티 주의 |
| `team`                   | `platform`                   | 팀별 합산                                           |
| `org.unit`               | `cloud-infra`                | (선택) 더 큰 조직 단위                              |

> 직접 API 키 / Bedrock / Vertex / Foundry 사용 시에는 Claude 계정이 없어
> `user.email`, `user.account_*` 가 비어 있습니다. 이 경우
> `OTEL_RESOURCE_ATTRIBUTES`로 `enduser.id=...`를 직접 주입해야 사용자 식별이 됩니다.

### `OTEL_RESOURCE_ATTRIBUTES` 형식 주의 (자주 틀림)

- **공백 불가**: `user.name=My User`는 **유효하지 않습니다**.
  값을 따옴표로 감싸도 따옴표가 값에 포함되어 버립니다.
- 형식: `key1=value1,key2=value2` — US-ASCII만 허용, 공백·쉼표·세미콜론·백슬래시·따옴표 금지.
- 한국어 등 비 ASCII는 퍼센트 인코딩(`%EA%B9%80`) 필요.

```bash
# ❌ 잘못된 예
OTEL_RESOURCE_ATTRIBUTES="user.name=Lim Jblim,team=platform team"
# ✅ 올바른 예
OTEL_RESOURCE_ATTRIBUTES="user.name=jblim,team=platform"
```

### Prometheus 측 변환 규칙

OTel 속성 이름의 `.` 은 Prometheus 라벨에서 `_` 로 바뀝니다.

```text
OTEL_RESOURCE_ATTRIBUTES="user.name=jblim,team=platform"
                                ↓
Prometheus 라벨:   user_name="jblim", team="platform"
Loki 인덱스 라벨:  {user_name="jblim", team="platform"}
```

### Grafana 쿼리 예시

메트릭 이름은 OTel SDK가 단위 접미사를 자동 부착합니다 (`tokens`, `USD`, `s` 등).
정확한 이름은 [§7 발행되는 메트릭](#7-발행되는-메트릭)을 참고하세요.

```promql
# 내 토큰 사용량 (지난 24h)
sum(increase(claude_code_token_usage_tokens_total{user_name="jblim"}[24h]))

# 팀별 누적 비용
sum by (team) (increase(claude_code_cost_usage_USD_total[7d]))

# 사람별 모델 분포
sum by (user_name, model) (rate(claude_code_token_usage_tokens_total[$__rate_interval]))
```

### 카디널리티 주의

Prometheus는 라벨 조합마다 별도 시계열을 만듭니다. 다음 상황에서 부담이 커집니다.

- 사용자 수 × 모델 수 × 도구 수 × …
- `user.email`처럼 도메인 포함된 긴 문자열은 저장 효율도 떨어짐
- `session.id` 등은 끝없이 증가 — 카디널리티 폭발 1순위

권장:

- 사내 사번(`user.id=E12345`) 같이 **짧고 안정적인 식별자**를 우선
- `user.email`은 추적용으로만 쓰거나 해시(`sha256` 앞 8자리)
- 1000명 이상 규모면 *roll-up recording rule* 을 만들어 대시보드는 집계 시계열을 보게 하기

### 메트릭 카디널리티 제어 환경변수

| 환경변수                            | 기본값 | 효과                                                |
| ----------------------------------- | ------ | --------------------------------------------------- |
| `OTEL_METRICS_INCLUDE_SESSION_ID`   | true   | `session_id` 라벨 포함 — **운영에선 false 권장**    |
| `OTEL_METRICS_INCLUDE_VERSION`      | false  | `app_version` 라벨 포함 — 버전별 추적이 필요할 때만 |
| `OTEL_METRICS_INCLUDE_ACCOUNT_UUID` | true   | `user_account_uuid`/`user_account_id` 라벨 포함     |

운영 규모가 커질수록 `INCLUDE_SESSION_ID=false`가 가장 큰 절감 효과를 냅니다.

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

사내 전체에 통일된 라벨 정책을 강제하려면 관리 설정 파일(MDM 배포)을 사용하세요.
사용자가 재정의할 수 없습니다. `agents/team-rollout.md` 참고.

## 4) 민감 콘텐츠 마스킹

데이터 노출 수준은 4단계 게이트로 제어됩니다 (각각 기본 off):

| 환경변수                  | 켜면 발생하는 일                                                                             |
| ------------------------- | -------------------------------------------------------------------------------------------- |
| `OTEL_LOG_USER_PROMPTS`   | `user_prompt` 이벤트의 `prompt` 속성에 실제 프롬프트 본문 포함                               |
| `OTEL_LOG_TOOL_DETAILS`   | `tool_result.tool_input`, `tool_parameters` (Bash 명령 전문, MCP 인자 등) 포함               |
| `OTEL_LOG_TOOL_CONTENT`   | 트레이스 스팬 이벤트에 도구 입력/출력 콘텐츠 포함 (스팬당 60KB 잘림). 트레이스 필수          |
| `OTEL_LOG_RAW_API_BODIES` | 전체 Anthropic Messages API 요청/응답 본문을 `api_request_body`/`_response_body` 로그로 발행 |

`OTEL_LOG_RAW_API_BODIES=file:/var/log/claude-bodies`로 디렉토리 모드를 켜면
이벤트엔 파일 포인터(`body_ref`)만 들어가고 본문은 디스크에 따로 기록됩니다 — 잘림 없음.
대용량/장기 보존 시 권장. 단, **본문에는 전체 대화 기록이 포함**되므로 보존·접근 통제 필수.

수집기 측 마스킹은 OTel Collector의 `attributes` processor를 사용합니다
(`docker-compose/configs/otel/otel-collector-config.yaml`의 `attributes/redact-prompts`
주석 참조).

## 5) 동작 확인

세션을 한 번 실행한 뒤:

```bash
# Prometheus에서 Claude Code 메트릭 조회
curl -s 'http://localhost:9090/api/v1/query?query=claude_code_session_count_total' | jq

# Loki 직접 조회 (이벤트 본문)
curl -s -G 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={service_name="claude-code"}' \
  --data-urlencode "start=$(date -v-1H +%s)000000000" \
  --data-urlencode "end=$(date +%s)000000000" | jq '.data.result | length'
```

Grafana > "LLM Overview" 대시보드에서 토큰/비용/세션 패널에 값이 나타나야 합니다.
"LLM by User / Team" 대시보드에서 user_name / team 라벨로 필터·그룹 가능합니다.

## 6) 메트릭과 이벤트 — 차이점

Claude Code가 발행하는 신호는 **두 가지로 명확히 나뉩니다**.

- **메트릭(OTLP metrics)** — 누적 카운터. Prom으로 가서 집계·시계열 쿼리에 사용. **8종뿐.**
- **이벤트(OTLP logs)** — 구조화된 도메인 이벤트. Loki/SIEM으로 가서 감사·드릴다운에 사용.
  20종 이상.

운영 중 흔히 "메트릭처럼 보이는" 것들 (예: API 호출 카운트, 도구 결정, 훅 실행)은 사실
**이벤트**입니다. LogQL `count_over_time(... | event_name="...")` 으로 카운트해야 합니다.

## 7) 발행되는 메트릭

OTel SDK의 **단위 접미사 자동 부여 규칙**:

- 단위 `count` → 접미사 없음, `_total` 부착
- 단위 `tokens` → `_tokens_total`
- 단위 `USD` → `_USD_total`
- 단위 `s` (seconds) → `_seconds_total`

| OTel 이름                             | Prometheus 이름                             | 단위   | 의미                                                                                                                       |
| ------------------------------------- | ------------------------------------------- | ------ | -------------------------------------------------------------------------------------------------------------------------- |
| `claude_code.session.count`           | `claude_code_session_count_total`           | count  | 세션 시작 수. 라벨: `start_type` (fresh/resume/continue)                                                                   |
| `claude_code.lines_of_code.count`     | `claude_code_lines_of_code_count_total`     | count  | 수정된 코드 라인 수. 라벨: `type` (added/removed)                                                                          |
| `claude_code.pull_request.count`      | `claude_code_pull_request_count_total`      | count  | 생성된 PR 수                                                                                                               |
| `claude_code.commit.count`            | `claude_code_commit_count_total`            | count  | 생성된 git 커밋 수                                                                                                         |
| `claude_code.cost.usage`              | `claude_code_cost_usage_USD_total`          | USD    | 누적 비용. 라벨: `model`, `query_source`, `speed`, `effort`, `agent.name`, `skill.name`, `plugin.name`, `marketplace.name` |
| `claude_code.token.usage`             | `claude_code_token_usage_tokens_total`      | tokens | 토큰 사용량. 라벨: `type` (input/output/cacheRead/cacheCreation) + 위 비용 라벨 동일                                       |
| `claude_code.code_edit_tool.decision` | `claude_code_code_edit_tool_decision_total` | count  | Edit/Write/NotebookEdit 권한 결정. 라벨: `tool_name`, `decision`, `source`, `language`                                     |
| `claude_code.active_time.total`       | `claude_code_active_time_seconds_total`     | s      | 활성 사용 시간. 라벨: `type` (user/cli)                                                                                    |

> **자주 헷갈리는 점**: 공식 문서엔 `api_request`, `api_error`가 메트릭 표에 없습니다.
> 이들은 **이벤트로만** 발행됩니다. "API 호출 수" 패널은 LogQL로 만들어야 합니다:
>
> ```logql
> sum by (model) (count_over_time({service_name="claude-code"} | event_name="api_request" [$__range]))
> ```

모든 메트릭에 부착되는 **표준 라벨**:

| 라벨                | 출처                                                                                         |
| ------------------- | -------------------------------------------------------------------------------------------- |
| `service_name`      | `service.name` 리소스 속성 (기본 `claude-code`)                                              |
| `service_version`   | Claude Code 버전                                                                             |
| `host_arch`, `os_*` | OS / 아키텍처                                                                                |
| `terminal_type`     | `iTerm.app` / `vscode` / `cursor` / `tmux` 등                                                |
| `organization_id`   | OAuth 인증 시 조직 UUID                                                                      |
| `user_account_uuid` | OAuth 인증 시 계정 UUID                                                                      |
| `user_email`        | OAuth 인증 시 이메일 (DISABLE 가능)                                                          |
| `user_id`           | 설치 단위 익명 ID                                                                            |
| `session_id`        | 세션 단위 — **카디널리티 폭발 1순위**. 운영에선 `OTEL_METRICS_INCLUDE_SESSION_ID=false` 권장 |
| `app_version`       | `OTEL_METRICS_INCLUDE_VERSION=true`일 때만 포함                                              |

## 8) 발행되는 이벤트 (Loki / SIEM)

`OTEL_LOGS_EXPORTER=otlp`일 때 `service_name="claude-code"` 스트림에 OTLP log record로
발행됩니다. 각 이벤트는 `event_name` structured metadata로 식별됩니다.

| `event_name`              | 발행 시점                                      | 주요 필드                                                                                                                                                                     |
| ------------------------- | ---------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `user_prompt`             | 사용자가 프롬프트 제출 시                      | `prompt_length`, `prompt` (게이트), `command_name`, `command_source`                                                                                                          |
| `api_request`             | Claude API 호출 1회당                          | `model`, `input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_creation_tokens`, `cost_usd`, `duration_ms`, `request_id`, `query_source`, `speed`, `effort`            |
| `api_error`               | API 호출 최종 실패 (모든 재시도 소진 후)       | `model`, `error`, `status_code`, `duration_ms`, `attempt`, `request_id`                                                                                                       |
| `api_retries_exhausted`   | 재시도 후 포기 시 (`api_error`와 함께)         | `total_attempts`, `total_retry_duration_ms`                                                                                                                                   |
| `api_request_body`        | `OTEL_LOG_RAW_API_BODIES` 활성 시 요청별       | `body` 또는 `body_ref`, `body_length`, `body_truncated`                                                                                                                       |
| `api_response_body`       | `OTEL_LOG_RAW_API_BODIES` 활성 시 응답별       | 위와 동일                                                                                                                                                                     |
| `tool_result`             | 도구 실행 완료 시                              | `tool_name`, `tool_use_id`, `success`, `duration_ms`, `error_type`, `decision_type`, `decision_source`, `tool_input_size_bytes`, `tool_result_size_bytes`, `mcp_server_scope` |
| `tool_decision`           | 도구 권한 결정 시                              | `tool_name`, `tool_use_id`, `decision` (accept/reject), `source`                                                                                                              |
| `permission_mode_changed` | 권한 모드 전환 시 (Shift+Tab, exit plan 등)    | `from_mode`, `to_mode`, `trigger`                                                                                                                                             |
| `auth`                    | `/login`·`/logout` 완료 시                     | `action`, `success`, `auth_method`, `error_category`, `status_code`                                                                                                           |
| `mcp_server_connection`   | MCP 서버 연결·해제·실패 시                     | `status`, `transport_type`, `server_scope`, `duration_ms`, `error_code`, `server_name` (게이트)                                                                               |
| `internal_error`          | Claude Code 내부 예외 포착 시                  | `error_name`, `error_code` (메시지·스택은 포함 안 됨)                                                                                                                         |
| `plugin_installed`        | `claude plugin install` 완료 시                | `plugin.name`, `plugin.version`, `marketplace.name`, `marketplace.is_official`, `install.trigger`                                                                             |
| `plugin_loaded`           | 세션 시작 시 활성 플러그인당 1회               | `plugin.name`, `plugin.scope`, `enabled_via`, `has_hooks`, `has_mcp`, `skill_path_count` 등                                                                                   |
| `skill_activated`         | 스킬 호출 시                                   | `skill.name`, `invocation_trigger`, `skill.source`                                                                                                                            |
| `at_mention`              | `@`-멘션 해석 시                               | `mention_type` (file/directory/agent/mcp_resource), `success`                                                                                                                 |
| `hook_registered`         | 세션 시작 시 구성된 훅당 1회                   | `hook_event`, `hook_type`, `hook_source`                                                                                                                                      |
| `hook_execution_start`    | 훅 실행 시작 시                                | `hook_event`, `hook_name`, `num_hooks`                                                                                                                                        |
| `hook_execution_complete` | 훅 실행 완료 시                                | `num_success`, `num_blocking`, `num_non_blocking_error`, `num_cancelled`, `total_duration_ms`                                                                                 |
| `hook_plugin_metrics`     | 공식 마켓플레이스 플러그인 훅이 메트릭 발행 시 | `plugin_id`, `hook_event`, 플러그인이 정의한 키 (최대 20)                                                                                                                     |
| `compaction`              | 대화 컴팩션 완료 시                            | `trigger` (auto/manual), `success`, `duration_ms`, `pre_tokens`, `post_tokens`, `error`                                                                                       |
| `feedback_survey`         | 세션 품질 설문 표시·응답 시                    | `event_type`, `appearance_id`, `survey_type`, `response`                                                                                                                      |

이벤트 상관관계: 모든 이벤트는 `prompt_id` 속성을 공유합니다. 단일 프롬프트가 일으킨
모든 활동(여러 api_request + 도구 실행)을 한 번에 추적하려면 같은 `prompt_id`로 필터링.

> `prompt_id`, `session_id`, `tool_use_id`는 카디널리티가 매우 높아 **메트릭 라벨로는 절대
> 쓰지 마세요**. 이벤트 분석 / 감사 추적 용도로만 사용.

## 9) 감사 / SIEM 연동

`OTEL_LOG_TOOL_DETAILS=1` + 이벤트 OTLP export 만으로 풍부한 감사 로그를 얻을 수 있습니다.

| 감지하고 싶은 신호                 | 이벤트                                             | 핵심 속성                                      |
| ---------------------------------- | -------------------------------------------------- | ---------------------------------------------- |
| 도구 호출 허용/거부, 그리고 어떻게 | `tool_decision`                                    | `decision`, `source`, `tool_name`              |
| 권한 모드 에스컬레이션             | `permission_mode_changed`                          | `from_mode`, `to_mode`, `trigger`              |
| 정책 훅이 작업을 차단함            | `hook_execution_complete`                          | `hook_event`, `num_blocking`                   |
| 로그인 / 로그아웃 / 인증 실패      | `auth`                                             | `action`, `success`, `error_category`          |
| MCP 서버 연결 및 실패              | `mcp_server_connection`                            | `status`, `server_name`, `error_code`          |
| 플러그인 설치 출처                 | `plugin_installed`                                 | `plugin.name`, `marketplace.is_official`       |
| 실행된 명령 / 터치된 파일          | `tool_result` (단, `OTEL_LOG_TOOL_DETAILS=1` 필요) | `tool_parameters` (Bash command, file_path 등) |

SIEM 전용 별도 엔드포인트로 이벤트만 보내고 싶다면 `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT`
환경변수로 메트릭과 분리 가능합니다.

## 10) 디버깅 팁

- **내보내기 간격이 너무 길어서 데이터가 안 보임**:
  메트릭 기본 60s, 로그 기본 5s. 디버깅 중엔 `OTEL_METRIC_EXPORT_INTERVAL=5000`,
  `OTEL_LOGS_EXPORT_INTERVAL=1000`으로 줄이고, 운영 복귀 시 다시 원복.
- **`console` exporter로 즉시 확인**:
  `OTEL_METRICS_EXPORTER=console,otlp` 하면 stdout으로도 같이 찍힘.
- **`OTEL_*` 가 하위 프로세스에 전파되지 않음**:
  Claude Code는 Bash 도구, 훅, MCP 서버, 언어 서버 등 자식 프로세스에 OTel 변수를
  **의도적으로 전달하지 않습니다**. 자식이 직접 텔레메트리를 발행해야 한다면 명령 안에서
  변수를 직접 export.
- **메트릭 이름이 문서와 달라 보임**:
  OTel SDK의 단위 접미사 규칙(§7 상단) 때문. `claude_code_token_usage_total`이 아니라
  `claude_code_token_usage_tokens_total` 입니다.
