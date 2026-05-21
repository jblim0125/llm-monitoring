# LLM 사용량 모니터링 스택 (자체 호스팅)

AI 코딩 에이전트(Claude Code, GitHub Copilot, OpenClaw 등)의
LLM 사용량 — **토큰, 비용, 세션, 모델 분포, 도구 호출, 지연 시간, 오류** —
을 사내 환경에서 자체 호스팅으로 수집·시각화하기 위한 풀스택 구성입니다.

[Microsoft Learn: Grafana로 AI 코딩 에이전트 모니터링](https://learn.microsoft.com/ko-kr/azure/managed-grafana/grafana-opentelemetry-app-insights)
문서에서 제시하는 아키텍처를 Azure 의존성 없이 다음과 같이 재구성했습니다.

```
원본:  Agent ──OTLP──> OTel Collector ──> Application Insights <──KQL── Grafana
사내:  Agent ──OTLP──> OTel Collector ──┬─> Prometheus  (metrics)
                                        ├─> Loki        (logs)
                                        └─> Tempo       (traces)
                                                 ▲
                                                 └─── Grafana
```

## 모니터링 대상 — OTLP 지원 여부에 따라 갈림

| 도구             | 인증 방식       | 로컬 OTLP 수집 가능? | 본 스택에서 다루는 방식 |
| ---------------- | --------------- | -------------------- | ----------------------- |
| Claude Code      | API 키 / 계정   | ✅ 네이티브           | 로컬에서 OTLP 직접 전송 |
| GitHub Copilot   | 계정 (VS Code)  | ✅ 네이티브           | VS Code 설정으로 OTLP 직접 전송 |
| OpenClaw         | 게이트웨이      | ✅ 네이티브           | 게이트웨이 telemetry 설정으로 직접 전송 |
| Codex            | **계정 로그인** | ❌ 클라우드에서 호출됨 | 제공자 측 admin export로 처리 (가이드 참조) |
| Cursor           | **계정 로그인** | ❌ 클라우드에서 호출됨 | 제공자 측 admin export로 처리 (가이드 참조) |

Codex, Cursor를 **API 키 기반**(즉 사용자가 OpenAI/Anthropic 키를 직접 입력)으로 쓰는
환경이라면 LiteLLM 같은 OpenAI 호환 게이트웨이를 끼워 가로챌 수 있지만, **계정 로그인**
환경에서는 LLM 호출이 Cursor/OpenAI 서버 측에서 일어나므로 로컬에서 잡을 수 없습니다.
이 경우 각 제공자가 제공하는 사용량 export/감사 로그를 사용해야 합니다 (`agents/codex.md`, `agents/cursor.md`).

---

## 디렉토리 구조

```
llm-monitoring/
├── README.md                   ← 이 파일 (개요/아키텍처)
├── docker-compose/             ← Docker Compose 환경
│   ├── docker-compose.yml
│   ├── .env.example
│   ├── configs/
│   │   ├── otel/otel-collector-config.yaml
│   │   ├── prometheus/prometheus.yml
│   │   ├── loki/loki-config.yaml
│   │   ├── tempo/tempo.yaml
│   │   └── grafana/
│   │       ├── provisioning/datasources/datasources.yaml
│   │       ├── provisioning/dashboards/dashboards.yaml
│   │       └── dashboards/
│   │           ├── llm-overview.json   ← 전체 합산
│   │           └── llm-by-user.json    ← 사용자 / 팀 단위
│   └── README.md
├── k8s/                        ← Kubernetes 환경 (원시 YAML)
│   ├── 00-namespace.yaml
│   ├── 10-prometheus.yaml
│   ├── 20-loki.yaml
│   ├── 30-tempo.yaml
│   ├── 40-otel-collector.yaml
│   ├── 50-grafana.yaml
│   └── README.md
├── agents/                     ← 에이전트별 로컬 연동 방법
│   ├── claude-code.md
│   ├── github-copilot.md
│   ├── openclaw.md
│   ├── codex.md
│   ├── cursor.md
│   └── team-rollout.md         ← 사용자/팀 라벨 사내 일괄 배포
└── scripts/                    ← 실행/검증 헬퍼 스크립트
    ├── docker-up.sh
    ├── docker-down.sh
    ├── k8s-apply.sh
    ├── k8s-delete.sh
    └── smoke-test.sh
```

---

## 빠르게 시작

### 1) Docker Compose (로컬 PoC)

```bash
cd docker-compose
cp .env.example .env            # 필요 시 비밀번호/포트 수정
docker compose up -d
```

- Grafana:    http://localhost:3000  (admin / admin — `.env`에서 변경)
- OTel OTLP:  http://localhost:4318  (HTTP) / `localhost:4317` (gRPC)
- Prometheus: http://localhost:9090
- Loki:       http://localhost:3100
- Tempo:      http://localhost:3200

### 2) Kubernetes (사내 클러스터)

```bash
cd k8s
kubectl apply -f 00-namespace.yaml
kubectl apply -f .                     # 순번대로 적용
kubectl -n llm-monitoring port-forward svc/grafana 3000:3000
```

자세한 옵션(NodePort, Ingress, 리소스 요청량)은 `k8s/README.md` 참조.

### 3) 에이전트 연결

`agents/` 폴더의 가이드대로 각 도구의 설정을 수정합니다.
공통 OTLP 엔드포인트는 `http://<수집기-호스트>:4318` 입니다.

각 사용자는 자기 설정에 다음 한 줄만 추가하면 Grafana의 "LLM by User / Team"
대시보드에서 사람·팀 단위로 잡힙니다.

```bash
OTEL_RESOURCE_ATTRIBUTES="service.name=claude-code,user.name=jblim,user.email=jblim@example.com,team=platform"
```

사내 일괄 배포(MDM/Settings Sync/dotfiles)는 `agents/team-rollout.md` 참고.

---

## 데이터 흐름과 보관 위치

| 신호 종류 | 수신 (OTel)     | 저장소     | 어떤 정보가 들어가나                        |
| --------- | --------------- | ---------- | ------------------------------------------- |
| Metrics   | OTLP/HTTP, gRPC | Prometheus | 토큰 수, 비용, 요청 수, 모델별 카운터 등    |
| Logs      | OTLP/HTTP, gRPC | Loki       | 사용자 프롬프트, 도구 호출, API 에러 메시지 |
| Traces    | OTLP/HTTP, gRPC | Tempo      | 세션·요청 단위 스팬, 지연 시간 분포         |

OTel Collector는 한 곳으로 수집 후 3개 백엔드로 *fan-out*합니다.
새 에이전트를 추가해도 수집기 설정은 그대로 두고 도구에서만 엔드포인트를 가리키면 됩니다.

---

## 보안 / 운영 메모

- `.env`는 git에 올리지 않습니다 (`.gitignore` 권장: `.env`, `data/`).
- 사내 배포 시 Grafana 관리자 비밀번호, Prometheus/Loki 외부 노출 여부를 반드시 검토하세요.
- 프롬프트 본문(`OTEL_LOG_USER_PROMPTS=1`)을 로깅하면
  규제 데이터가 Loki에 들어갈 수 있습니다.
  민감 환경에서는 끄거나 OTel processor의 `attributes`/`redaction` 단계로
  마스킹하세요. 예시는 `docker-compose/configs/otel/otel-collector-config.yaml`
  주석을 참고하세요.

---

## 참고

- [OpenTelemetry Collector Contrib](https://github.com/open-telemetry/opentelemetry-collector-contrib)
- [Grafana - Azure Monitor 대시보드 원본 (Microsoft Learn)](https://learn.microsoft.com/ko-kr/azure/managed-grafana/grafana-opentelemetry-app-insights)
- [Claude Code 모니터링 문서](https://code.claude.com/docs/en/monitoring-usage)
- [GitHub Copilot 에이전트 모니터링](https://code.visualstudio.com/docs/copilot/guides/monitoring-agents)
