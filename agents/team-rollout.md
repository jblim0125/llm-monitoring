# 사내 일괄 배포 가이드

개별 개발자가 자기 PC의 설정 파일에 OTLP 엔드포인트와 사번/팀 라벨을
손으로 적게 두면, 누가 빼먹고 누가 오타 내는지에 따라 데이터가 들쭉날쭉합니다.
**팀 단위로 한 번에 같은 라벨 정책을 적용하는 패턴** 세 가지를 정리합니다.

## 패턴 1 — 쉘 rc 템플릿 + 사번 매크로 (가장 단순)

사내 dotfiles 저장소 / 신입 온보딩 스크립트에 다음을 포함시킵니다.

```bash
# ~/.zshrc / ~/.bashrc 자동 추가
# (각 사용자의 사번/팀은 사내 디렉토리 서비스에서 가져오거나 prompt로 입력받음)
export LLM_USER_NAME="$(whoami)"                       # 또는 사번
export LLM_USER_EMAIL="$(git config user.email)"       # 보통 사내 이메일과 동일
export LLM_TEAM="${LLM_TEAM:-unassigned}"              # 사용자가 한 번만 설정

# 모든 OTel-aware 도구가 공유하는 표준 변수
export OTEL_EXPORTER_OTLP_ENDPOINT="http://otel.사내.example.com:4318"
export OTEL_EXPORTER_OTLP_PROTOCOL="http/protobuf"
export OTEL_RESOURCE_ATTRIBUTES="user.name=${LLM_USER_NAME},user.email=${LLM_USER_EMAIL},team=${LLM_TEAM},deployment.environment=corp"
```

이후 도구별 settings.json은 **엔드포인트와 service.name만** 적어도 됩니다.
표준 OTel 변수는 위 쉘에서 자동 상속.

```jsonc
// ~/.claude/settings.json (개인은 service.name만 신경 쓰면 됨)
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp"
    // OTEL_RESOURCE_ATTRIBUTES, OTEL_EXPORTER_OTLP_ENDPOINT 는 쉘 환경 상속
  }
}
```

장점: 가장 간단. 단점: GUI에서 띄운 VS Code는 쉘 rc를 안 읽으므로 패턴 2 또는 3 병행 필요.

## 패턴 2 — VS Code Settings Sync (Profile 푸시)

VS Code의 **Settings Sync**를 사내 GitHub Enterprise / Azure DevOps와 연결하면,
관리자가 만든 **Profile** 을 팀 전원이 가져갈 수 있습니다.

`team-llm-observability.code-profile` 같은 파일을 만들고 다음 내용을 포함:

```json
{
  "settings": {
    "github.copilot.chat.otel.enabled": true,
    "github.copilot.chat.otel.exporterType": "otlp-http",
    "github.copilot.chat.otel.otlpEndpoint": "http://otel.사내.example.com:4318",
    "github.copilot.chat.otel.serviceName": "copilot-chat",
    "github.copilot.chat.otel.captureContent": false,
    "terminal.integrated.env.osx": {
      "OTEL_RESOURCE_ATTRIBUTES": "service.name=copilot-chat,user.name=${env:USER},team=${env:LLM_TEAM},deployment.environment=corp"
    },
    "terminal.integrated.env.linux": {
      "OTEL_RESOURCE_ATTRIBUTES": "service.name=copilot-chat,user.name=${env:USER},team=${env:LLM_TEAM},deployment.environment=corp"
    },
    "terminal.integrated.env.windows": {
      "OTEL_RESOURCE_ATTRIBUTES": "service.name=copilot-chat,user.name=${env:USERNAME},team=${env:LLM_TEAM},deployment.environment=corp"
    }
  }
}
```

사용자별 사번/이메일/팀은 `${env:USER}` / `${env:LLM_TEAM}` 매크로로 받아 옵니다.
이 환경변수는 패턴 1의 쉘 rc 또는 패턴 3의 MDM에서 사전 주입.

VS Code → "Settings > Profile > Apply Profile from URL" 으로 사내 호스팅된 URL에서 받게
하거나, 신입 온보딩 봇이 자동으로 import 시키게 합니다.

## 패턴 3 — MDM / Group Policy (강제)

Jamf, Intune, Workspace ONE 같은 MDM이 있다면 환경변수를 OS 레벨에서 강제로 주입할 수 있습니다.

### macOS — launchd plist

```xml
<!-- /Library/LaunchAgents/com.example.llm-env.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.example.llm-env</string>
  <key>RunAtLoad</key><true/>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/launchctl</string>
    <string>setenv</string>
    <string>OTEL_EXPORTER_OTLP_ENDPOINT</string>
    <string>http://otel.사내.example.com:4318</string>
  </array>
</dict>
</plist>
```

```bash
sudo launchctl load /Library/LaunchAgents/com.example.llm-env.plist
# 또는 MDM이 위 plist를 푸시
```

`setenv` 는 launchd가 띄우는 모든 GUI 앱이 상속받는 전역 환경변수입니다.
VS Code를 Spotlight에서 띄워도 적용됨.

### Linux — `/etc/environment`

```
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel.사내.example.com:4318
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
```

사용자별 라벨은 `/etc/profile.d/llm-env.sh` 에서 LDAP/사내 디렉토리 lookup 후 export.

### Windows — Group Policy

`User Configuration > Preferences > Windows Settings > Environment` 항목에서
`OTEL_EXPORTER_OTLP_ENDPOINT` 등을 등록하면 도메인 가입된 PC에 자동 배포됩니다.
사용자 식별자는 `%USERNAME%` 매크로 사용.

## 권장 조합

규모와 거버넌스 수준에 따라:

| 팀 규모          | 권장 패턴                        |
| ---------------- | -------------------------------- |
| 개인 / 5명 이하   | 패턴 1 (쉘 rc) 만               |
| 5~30명 (스쿼드)  | 패턴 1 + 패턴 2 (Profile)        |
| 30명 이상 / 전사 | 패턴 3 (MDM) + 패턴 2 보강       |

## 검증 체크리스트

배포 후 다음 PromQL을 Grafana에서 실행해 라벨이 잘 들어오는지 확인하세요.

```promql
# 라벨이 누락된 시계열 — 'unassigned' 또는 비어있는 user_name
count by (user_name) (claude_code_session_count_total{user_name=~"^(|unassigned)$"})

# 팀별 활성 사용자 수
count by (team) (count by (team, user_name) (claude_code_session_count_total))

# 최근 24h 라벨이 빠진 호스트
sum by (host_name) (rate(claude_code_session_count_total{user_name=""}[24h]))
```

값이 나오면 해당 호스트/사용자의 설정이 빠진 것이니 1:1 안내.
