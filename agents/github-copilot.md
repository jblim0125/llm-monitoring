# GitHub Copilot (VS Code) 연동

GitHub Copilot의 Chat/Agent 모드는 VS Code 설정으로 OpenTelemetry 신호를 발행할 수 있습니다.
공식 문서: https://code.visualstudio.com/docs/copilot/guides/monitoring-agents

## 1) 설정 위치

VS Code `settings.json`:

- macOS:    `~/Library/Application Support/Code/User/settings.json`
- Linux:    `~/.config/Code/User/settings.json`
- Windows:  `%APPDATA%\Code\User\settings.json`

또는 워크스페이스 단위로 `<repo>/.vscode/settings.json`.

## 2) 추가할 항목

```json
{
  "github.copilot.chat.otel.enabled": true,
  "github.copilot.chat.otel.exporterType": "otlp-http",
  "github.copilot.chat.otel.otlpEndpoint": "http://localhost:4318",
  "github.copilot.chat.otel.captureContent": true,
  "github.copilot.chat.otel.serviceName": "copilot-chat",

  // 사용자/팀 식별을 위한 환경변수 — VS Code의 통합 터미널 및 자식 프로세스에 주입
  "terminal.integrated.env.osx": {
    "OTEL_RESOURCE_ATTRIBUTES": "service.name=copilot-chat,user.name=jblim,user.email=jblim@example.com,team=platform"
  },
  "terminal.integrated.env.linux": {
    "OTEL_RESOURCE_ATTRIBUTES": "service.name=copilot-chat,user.name=jblim,user.email=jblim@example.com,team=platform"
  },
  "terminal.integrated.env.windows": {
    "OTEL_RESOURCE_ATTRIBUTES": "service.name=copilot-chat,user.name=jblim,user.email=jblim@example.com,team=platform"
  }
}
```

`captureContent: true`는 프롬프트 본문을 포함합니다. 규제 환경에서는 `false`로 두세요.

VS Code를 재시작하고 Copilot Chat을 한 번 사용한 뒤 Grafana에서 확인합니다.

## 3) 사용자 / 팀 라벨 주입 — VS Code 특이사항

Copilot Extension은 표준 OpenTelemetry SDK를 통해 동작하므로,
**`OTEL_RESOURCE_ATTRIBUTES` 환경변수를 VS Code 프로세스 자신이 볼 수 있어야**
사용자/팀 라벨이 텔레메트리에 붙습니다. macOS / Linux는 GUI에서 클릭으로 실행하면
shell rc가 안 읽혀서 이 변수가 빠집니다. 다음 3가지 중 하나를 쓰세요.

### 방법 A — `terminal.integrated.env.*` (가장 간단, 위 예시)

VS Code가 자식 프로세스(Copilot extension worker 포함)에 이 환경을 상속시킵니다.
**Copilot Chat 호출은 이 환경을 받습니다.** 사용자마다 settings.json만 수정하면 됨.

> 참고: `terminal.integrated.env.*` 는 통합 터미널에만 적용된다고 문서에 나오지만,
> 실제로는 extension host 가 같은 env를 상속받기 때문에 Copilot에도 효과가 있습니다.
> 일부 VS Code 버전에선 동작이 다를 수 있어, 안 되면 방법 B 사용.

### 방법 B — 셸 rc로 export 후 터미널에서 VS Code 실행 (확실)

```bash
# ~/.zshrc 또는 ~/.bashrc 에 추가
export OTEL_RESOURCE_ATTRIBUTES="service.name=copilot-chat,user.name=jblim,user.email=jblim@example.com,team=platform"

# VS Code는 반드시 터미널에서 실행
$ code .
```

macOS Spotlight / Dock에서 클릭으로 띄우는 평소 습관이라면, `~/.zprofile` 에
같은 export를 넣고 `defaults write` 로 launchd가 환경변수를 보게 만들거나
방법 A로 가는 게 깔끔합니다.

### 방법 C — Settings Sync / Profile Sync (팀 일괄 배포)

사내 팀 전원에게 같은 라벨 정책을 강제하려면 VS Code의 **Settings Sync** 또는
**Profile** 기능을 활용해 공통 settings.json을 푸시합니다.
사용자 식별자 부분만 매크로(`${USER}`, `${env:USER_EMAIL}` 등)로 처리하면 1회 작성으로 전사 적용 가능.
자세한 패턴은 `team-rollout.md` 참고.

### 권장 키 세트 (Claude Code 와 동일)

| 키                       | 예시                | 비고                         |
| ------------------------ | ------------------- | ---------------------------- |
| `service.name`           | `copilot-chat`      | 대시보드 `agent` 라벨로 정규화 |
| `user.name`              | `jblim`             | 사번/로그인 ID 권장          |
| `user.email`             | `jblim@example.com` | 카디널리티 주의              |
| `team`                   | `platform`          | 팀별 합산                    |
| `org.unit`               | `cloud-infra`       | (선택)                       |
| `deployment.environment` | `local`             | 환경                         |

## 4) 발행되는 주요 신호

GitHub Copilot은 OTel 의미 규약(`gen_ai.*`)을 따르며 다음과 같은 메트릭을 보냅니다.

- 작업(operation) 수
- 입력 / 출력 토큰 (히스토그램)
- 채팅 세션 시작 수
- 도구 호출 수 (`tool_call`)
- TTFT (Time-To-First-Token), 모델별 P50/P90
- 응답 지연 시간

Prometheus에서는 다음 형태로 보입니다:

```
gen_ai_client_token_usage_sum{
  gen_ai_token_type="input",
  gen_ai_request_model="gpt-4o",
  user_name="jblim", team="platform"
}
gen_ai_client_operation_duration_bucket{...}
```

## 5) 확인

```bash
# 코파일럿이 데이터를 보내고 있는지
curl -s 'http://localhost:9090/api/v1/query?query=sum(rate(gen_ai_client_token_usage_sum[5m]))' | jq

# 내 데이터만
curl -s 'http://localhost:9090/api/v1/query?query=sum(rate(gen_ai_client_token_usage_sum{user_name="jblim"}[5m]))' | jq

# Loki 로그
curl -s -G 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={service_name="copilot-chat", user_name="jblim"}' | jq '.data.result | length'
```

## 6) 비고

- Copilot의 OTel 출력 기능은 비교적 새 기능이라 VS Code/Copilot Extension 버전이 최신이어야 합니다.
- 엔터프라이즈 환경에서는 `Copilot Business`/`Copilot Enterprise` 정책에 따라
  텔레메트리가 차단되어 있을 수 있습니다. GitHub 조직 관리자에게 확인 필요.
- IntelliJ/JetBrains 측 Copilot은 본 글 작성 시점에 OTel export를 공식 지원하지 않습니다.
