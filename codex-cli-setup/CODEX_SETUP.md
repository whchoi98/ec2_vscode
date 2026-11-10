# Codex CLI 설정

VSCode Server에서 Codex CLI를 설치하고 사용자 `config.toml`을 구성합니다. 2026-11-08에 이 EC2의 Codex CLI 0.167.0과 `~/.codex/config.toml`을 확인해, Bedrock 인증 키를 제외한 전체 설정을 예제에 반영했습니다.

## 비교 결과

| 항목 | 기존 프로젝트 | 갱신한 설정 |
|------|---------------|-------------|
| 모델 저장 위치 | `.bashrc`의 `CODEX_DEFAULT_MODEL` | `config.toml`의 `model` |
| Bedrock 연결 | 프록시 URL과 `OPENAI_API_KEY` 입력 | 내장 `amazon-bedrock` provider와 AWS 인증 |
| 새 설정의 모델 | 스크립트마다 서로 다른 이전 모델 | 현재 환경의 `openai.gpt-6-astra` |
| 추론·컨텍스트 | 설정 없음 | 위 모델의 기본 예제는 `max`, 1,048,576 토큰 |
| 승인·샌드박스 | 이전 승인 모드 환경변수 | `on-request`, `auto_review`, `workspace-write` |
| 상태 표시줄 | 설정 없음 | 현재 환경의 모델·작업·경로·브랜치·컨텍스트 항목 |
| MCP 저장 위치 | `~/.codex/mcp.json` | `config.toml`의 `[mcp_servers]` |
| CLI 업데이트 | `sudo npm install -g` | 현재 실행 중인 CLI의 `codex update` 우선 사용 |

현재 환경에서 사용하는 Bedrock Mantle 설정을 기본 예제로 제공합니다. 기존 파일에 모델, provider, 승인 정책, 상태 표시줄이 있으면 그 값을 유지합니다. 다른 모델을 선택할 때는 해당 모델이 지원하는 추론 수준과 컨텍스트 크기를 사용하세요. 명시적으로 모델이나 provider를 바꾸면 이전 모델의 강제 컨텍스트 길이와 추론 수준을 제거합니다.

[config.example.toml](config.example.toml)에는 이 EC2의 다음 설정이 모두 들어 있습니다.

| 설정 | 포함한 내용 |
|------|-------------|
| 모델·provider | `openai.gpt-6-astra`, `amazon-bedrock`, `max`, 컨텍스트 1,048,576, 서비스 등급 `default` |
| 엔드포인트·리전 | `openai_base_url`의 Bedrock Mantle 주소, `us-east-1` |
| 승인 검토 | `approvals_reviewer = "auto_review"` |
| 프로젝트 신뢰 | `/home/ec2-user`와 프로젝트별 경로를 포함한 21개 항목 |
| TUI | 상태 표시줄 8개 항목, 색상 사용, 화면 읽기 프로그램 감지 상태, 모델 안내 표시 상태 |
| MCP | `seoul-opendata`의 `node` 명령과 실제 서버 파일 경로 |
| 추가 쓰기 경로 | `/home/ec2-user/my-project` |
| 플러그인 | `codex-hud@personal`, `codex-project-init@personal`, `my-workshop@personal` 활성화 |

확인 시점의 `config.toml`에는 Bedrock 키가 직접 저장되어 있지 않았습니다. 예제에도 인증 키를 넣지 않았으며, 별도 인증 파일과 환경변수 값은 복사하지 않습니다.

## 사전 요구사항

| 항목 | 확인 명령 | 필요한 경우 |
|------|-----------|-------------|
| Codex CLI | `codex --version` | 실행 및 설정 검증. 이 가이드는 0.167.0에서 검증 |
| Node.js / npm | `node --version`, `npm --version` | npm으로 신규 설치하거나 이전 CLI를 갱신할 때 |
| Python / tomlkit | `python3 -c 'import tomlkit'` | 설정 병합. Python 3.9 이상 |
| uv / uvx | `uv --version`, `uvx --version` | tomlkit 실행 환경 준비, 선택 사항인 AWS MCP 실행 |
| AWS 인증 | AWS 프로파일 또는 EC2 인스턴스 역할 | Bedrock와 AWS MCP를 사용할 때 |

Python에 tomlkit이 있으면 그대로 사용합니다. 없으면 설치된 `uv`로 별도 실행 환경을 준비합니다. 둘 다 없다면 다음과 같이 준비할 수 있습니다.

```bash
python3 -m pip install --user 'tomlkit>=0.13,<1'
```

Bedrock에는 선택한 모델을 호출할 AWS 권한과 해당 리전의 모델 접근 권한이 필요합니다. EC2 역할, 공유 AWS 설정 파일, SSO 프로파일 등 기존 AWS 인증 체인을 사용할 수 있습니다. Bedrock용 `OPENAI_API_KEY`나 프록시 URL을 입력할 필요는 없습니다.

## 빠른 시작

프로젝트 루트에서 실행합니다.

```bash
# 1. CLI 설치 또는 업데이트
bash codex-cli-setup/03-update-codex.sh

# 최초 npm 설치로 PATH가 추가된 경우 현재 셸에도 적용
source ~/.bashrc

# 2. 변경 계획 확인
bash codex-cli-setup/01-setup-env.sh --yes --dry-run

# 3. 기존 값 또는 현재 환경을 기준으로 한 기본값으로 설정
bash codex-cli-setup/01-setup-env.sh --yes

# 4. 실행 후 /status와 /model에서 provider 및 모델 확인
codex
```

기본 저장 위치는 `${CODEX_HOME:-$HOME/.codex}/config.toml`입니다. `--config-file`로 다른 파일을 지정할 수 있습니다. 공급자 설정은 사용자 설정 파일에 저장해야 합니다. 프로젝트의 `.codex/config.toml`에는 provider 관련 키가 허용되지 않습니다.

## 01-setup-env.sh — 모델과 실행 설정

인자 없이 실행하면 provider, 모델, 추론 수준, 승인 검토 방식을 입력받습니다. Bedrock을 선택하면 리전과 AWS 프로파일도 입력받습니다.

```bash
bash codex-cli-setup/01-setup-env.sh

# 현재 환경의 주요 값을 명시적으로 적용
bash codex-cli-setup/01-setup-env.sh --yes \
  --provider bedrock \
  --model openai.gpt-6-astra \
  --reasoning-effort max \
  --approvals-reviewer auto_review \
  --region us-east-1

# AWS SSO 프로파일 사용
bash codex-cli-setup/01-setup-env.sh --yes --aws-profile development

# 저장된 프로파일을 제거하고 AWS 기본 인증 체인 사용
bash codex-cli-setup/01-setup-env.sh --yes --aws-profile ''
```

`auto_review`는 승인 요청의 검토자를 지정합니다. 샌드박스를 해제하지 않습니다. 기존 `sandbox_mode`와 권한 설정은 유지하며, 새 파일에는 `workspace-write`를 사용합니다. 이미 `default_permissions`를 사용하는 파일에는 충돌하는 `sandbox_mode`를 추가하지 않습니다.

기본 실행은 위의 모델·실행 설정을 구성합니다. 예제에 담긴 이 EC2의 전체 설정은 다음 옵션으로 함께 병합할 수 있습니다.

### 이 EC2의 전체 설정 포함

```bash
# 변경 계획 확인
bash codex-cli-setup/01-setup-env.sh --yes --include-ec2-settings --dry-run

# 현재 사용자 설정에 누락된 항목 병합
bash codex-cli-setup/01-setup-env.sh --yes --include-ec2-settings
```

`--include-ec2-settings`는 `config.example.toml`을 읽어 프로젝트 신뢰 경로, MCP, 플러그인, 추가 쓰기 경로와 TUI 세부 설정까지 병합합니다. 같은 설정이 이미 있으면 기존 값을 유지합니다. 같은 이름의 MCP 서버는 명령과 인자를 하나의 설정으로 보존합니다. 기존 `default_permissions`가 있으면 충돌하는 이전 샌드박스 설정은 추가하지 않습니다.

예제의 `/home/ec2-user/...` 경로는 이 EC2의 실제 경로입니다. 다른 환경에 적용할 때는 예제의 프로젝트·쓰기 허용·MCP 실행 경로를 해당 환경에 맞게 수정하세요. 플러그인과 MCP의 실행 파일도 준비되어 있어야 합니다. 여기서는 해당 프로그램의 설치가 아니라 Codex 설정 등록을 수행합니다.

OpenAI 등 다른 provider를 함께 지정하면 예제의 Bedrock 엔드포인트와 모델별 추론·컨텍스트 설정은 가져오지 않습니다. 기존 파일에 이미 저장된 엔드포인트는 아래 전환 안내에 따라 확인하세요.

### OpenAI 사용

사용 가능한 모델 ID는 계정의 `/model` 목록에서 확인합니다. 다른 provider로 바꿀 때는 모델 ID도 함께 지정합니다.

```bash
bash codex-cli-setup/01-setup-env.sh --yes \
  --provider openai --model YOUR_AVAILABLE_MODEL_ID

# ChatGPT 로그인
codex login

# 또는 이미 환경변수에 보관한 API 키로 로그인
printenv OPENAI_API_KEY | codex login --with-api-key
```

이전 프록시 설정을 사용했다면 `OPENAI_BASE_URL` 환경변수와 `config.toml`의 `openai_base_url`도 확인하세요. OpenAI 기본 엔드포인트로 전환하려면 해당 프록시 설정을 제거해야 합니다.

### OpenAI 호환 API 사용

Responses API를 지원하는 엔드포인트를 지정합니다.

```bash
bash codex-cli-setup/01-setup-env.sh --yes \
  --provider custom \
  --model YOUR_GATEWAY_MODEL_ID \
  --base-url https://gateway.example.com/v1
```

`model_providers.openai-compatible`에 `wire_api = "responses"`와 `env_key = "OPENAI_API_KEY"`를 기록합니다. API 키는 실행 환경에서 제공하며, 스크립트는 키를 입력받거나 `.bashrc`에 저장하지 않습니다.

## 02-setup-mcp-servers.sh — AWS MCP 등록 (선택)

현재 필요한 MCP만 사용할 경우 이 단계는 생략할 수 있습니다. 실행하면 기존 서버를 보존하면서 다음 AWS MCP 서버를 추가합니다.

| 서버 | 실행 패키지 |
|------|-------------|
| `awslabs-terraform-mcp-server` | `awslabs.terraform-mcp-server@latest` |
| `awslabs-core-mcp-server` | `awslabs.core-mcp-server@latest` |
| `bedrock-agentcore-mcp-server` | `awslabs.amazon-bedrock-agentcore-mcp-server@latest` |

```bash
bash codex-cli-setup/02-setup-mcp-servers.sh --dry-run
bash codex-cli-setup/02-setup-mcp-servers.sh
codex mcp list
```

- 같은 이름의 서버가 `config.toml`에 있으면 명령어, 환경변수, 활성화 상태를 유지합니다.
- 설정 파일과 같은 디렉터리에 이전 `mcp.json`이 있으면 함께 병합합니다. `disabled`는 Codex의 `enabled`로 변환합니다. 이전 파일은 보관합니다.
- 새 서버는 PATH에서 `uvx`를 찾으며, 최초 패키지 실행을 고려해 시작 제한 시간을 60초로 설정합니다.
- 개별 서버의 활성화는 `config.toml`에서 `enabled = false`로 조정할 수 있습니다.

새 MCP를 추가할 때는 Codex의 기본 명령도 사용할 수 있습니다.

```bash
codex mcp add my-server -- node /absolute/path/to/server.js
```

## 03-update-codex.sh — 설치와 업데이트

현재 실행 경로를 출력하고, 설치된 CLI가 지원하면 `codex update`를 실행합니다. 신규 설치 또는 이 명령이 없는 이전 CLI에는 npm을 사용합니다.

```bash
bash codex-cli-setup/03-update-codex.sh --dry-run
bash codex-cli-setup/03-update-codex.sh
```

npm 설치의 기본 경로는 `~/.npm-global`이며, `.bashrc`에 PATH를 한 번 추가합니다. `sudo npm`을 사용하지 않으므로 사용자 설치본과 시스템 설치본을 혼동하는 일을 줄입니다. `CODEX_INSTALL_PREFIX`와 `CODEX_SHELL_RC`로 npm 설치 경로와 PATH 기록 파일을 지정할 수 있습니다. 이 두 값은 기존 CLI의 자체 업데이트에는 적용되지 않습니다.

`01-setup-openai-env.sh`와 `02-install-codex.sh`는 이전 경로와의 호환을 위해 각각 `01-setup-env.sh`, `03-update-codex.sh`를 호출합니다. `01-setup-openai-env.sh`에서도 OpenAI를 명시하려면 `--provider openai --model ...`을 지정하세요.

## 백업과 검증

TOML의 주석과 기존 MCP·플러그인·프로젝트 설정을 보존합니다. 변경이 있을 때만 `config.toml.backup.<시각>.<고유값>`을 만든 뒤 임시 파일을 원본과 교체합니다. 새 설정 파일과 백업은 현재 사용자만 읽고 쓸 수 있는 권한(`0600`)으로 생성합니다. 문법이 잘못된 설정은 덮어쓰지 않습니다.

`--dry-run`은 설정 파일과 백업을 만들지 않습니다. Python 실행 환경이 없어서 `uv`를 사용하는 경우에는 의존성 캐시가 생성될 수 있습니다. 기존의 `CODEX_DEFAULT_MODEL`, `CODEX_APPROVAL_MODE` 셸 항목은 더 이상 이 스크립트에서 생성하지 않습니다.

```bash
# 설정 병합·보존·마이그레이션 및 설치 경로 테스트
python3 -m unittest discover -s codex-cli-setup/tests -v

# Python 의존성을 uv로 준비해 테스트
uv run --no-project --with 'tomlkit>=0.13,<1' \
  python -m unittest discover -s codex-cli-setup/tests -v

# Codex 자체의 엄격한 설정 검사 (0.167.0에서 검증)
codex app-server --strict-config --print-startup-config
```

테스트는 임시 파일과 설치 명령 대역을 사용합니다. 실제 사용자 설정 변경, npm 패키지 설치, Bedrock 모델 호출은 수행하지 않습니다.

## 공식 문서

- [Codex 설정 참조](https://learn.chatgpt.com/docs/config-file/config-reference)
- [Amazon Bedrock 설정](https://learn.chatgpt.com/docs/amazon-bedrock) — Mantle과 Runtime의 provider 및 모델 ID 차이 포함
- [MCP 설정](https://learn.chatgpt.com/docs/extend/mcp)
