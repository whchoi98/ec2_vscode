# Codex CLI Setup Scripts

VSCode Server 내에서 OpenAI Codex CLI 환경을 구성하는 스크립트 모음입니다.
GPT-6 Astra의 OpenAI 직접 접속 및 Amazon Bedrock 연결 절차는 [README의 설치 및 설정 안내](../README.md)를 따릅니다.

## 사전 요구사항

| 항목 | 설치 확인 | 설치 방법 |
|------|----------|-----------|
| Codex CLI | `codex --version` | `npm install -g @openai/codex` (03번 스크립트) |
| Node.js / npm | `node --version` | `sudo dnf install -y nodejs` |
| uv / uvx | `uvx --version` | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| AWS CLI | `aws --version` | UserData에서 자동 설치됨 |
| jq | `jq --version` | `sudo dnf install -y jq` |

## 스크립트의 역할

| 스크립트 | 역할 및 적용 범위 |
|----------|------------------|
| `03-update-codex.sh` | Codex CLI 설치/업데이트 |
| `01-setup-env.sh` | API 키, Base URL, 선택한 모델 문자열을 `~/.bashrc`에 저장. 로그인 및 Codex 프로필 설정은 별도 |
| `02-setup-mcp-servers.sh` | `~/.codex/mcp.json` 생성. 현재 Codex 설정으로는 자동 적용되지 않음 |

현재 Codex의 모델과 MCP 설정은 `~/.codex/config.toml` 또는 프로필 파일에서 관리합니다.
MCP 서버를 등록하려면 아래의 `codex mcp add` 명령을 사용합니다.

---

## 01-setup-env.sh

Codex CLI 실행에 필요한 환경변수를 `~/.bashrc`에 설정합니다.

<strong>실행:</strong>
```bash
bash codex-cli-setup/01-setup-env.sh
source ~/.bashrc
```

<strong>대화형 입력 항목:</strong>

- API Provider 선택 (OpenAI / Amazon Bedrock / 커스텀)
- API 키 (필수, 입력 내용 숨김) - 선택한 Provider에서 발급한 키를 `OPENAI_API_KEY` 환경변수에 저장합니다. Bedrock 선택 시 Amazon Bedrock API 키를 입력하며, OpenAI Platform API 키를 입력하지 않습니다.
- `OPENAI_BASE_URL` - Base URL (Bedrock/커스텀 선택 시)
- 모델 선택: 스크립트 기본값은 `gpt-5.3-codex`. GPT-6 Astra는 `7`(직접 입력)을 선택하고 OpenAI 직접 접속에는 `gpt-6-astra`, Bedrock에는 `openai.gpt-6-astra` 입력

<strong>설정되는 환경변수:</strong>

```bash
OPENAI_API_KEY          # API 인증 키
OPENAI_BASE_URL         # (Bedrock/커스텀 시) API Base URL
CODEX_DEFAULT_MODEL     # 스크립트가 기록하는 모델 문자열
```

현재 Codex에서 사용할 모델은 `--model` 또는 설정 파일의 `model`로 지정합니다.
`CODEX_DEFAULT_MODEL`을 저장하는 것만으로 모델 설정이 완료된 것으로 간주하지 않습니다.

---

## MCP 서버 설정

`02-setup-mcp-servers.sh`는 JSON 파일을 생성합니다.
현재 Codex가 읽는 MCP 설정은 `config.toml`의 `[mcp_servers.<이름>]`입니다.
기존 JSON 파일이 있다면 내용을 확인하고 필요한 서버를 아래 명령으로 등록합니다.

```bash
codex mcp add awslabs-terraform-mcp-server \
  --env FASTMCP_LOG_LEVEL=ERROR \
  -- uvx awslabs.terraform-mcp-server@latest

codex mcp add awslabs-core-mcp-server \
  --env FASTMCP_LOG_LEVEL=ERROR \
  --env aws-foundation=true \
  --env solutions-architect=true \
  -- uvx awslabs.core-mcp-server@latest

codex mcp add bedrock-agentcore-mcp-server \
  --env FASTMCP_LOG_LEVEL=ERROR \
  -- uvx awslabs.amazon-bedrock-agentcore-mcp-server@latest

codex mcp list
```

<strong>등록 대상 MCP 서버:</strong>

| 서버 | 패키지 | 기능 |
|------|--------|------|
| awslabs-terraform-mcp-server | `awslabs.terraform-mcp-server` | Terraform/Terragrunt AWS 인프라 개발 |
| awslabs-core-mcp-server | `awslabs.core-mcp-server` | AWS API, Cost Explorer, 다이어그램, 가격 분석 |
| bedrock-agentcore-mcp-server | `awslabs.amazon-bedrock-agentcore-mcp-server` | Bedrock AgentCore Gateway, Memory, Runtime |

<strong>설정 파일:</strong>

```
~/.codex/config.toml
```

MCP 도구의 AWS 작업에는 별도의 AWS 자격 증명이 필요합니다. Bedrock 추론용 API 키만 입력해도 모든 AWS 도구에 인증되는 것은 아닙니다.
참고: [Codex MCP 설정 공식 문서](https://developers.openai.com/codex/mcp).

---

## 03-update-codex.sh

Codex CLI를 설치하거나 최신 버전으로 업데이트합니다.

<strong>실행:</strong>
```bash
bash codex-cli-setup/03-update-codex.sh
```

<strong>동작:</strong>

1. Node.js 설치 확인
2. 현재 버전 출력 (이미 설치된 경우)
3. `sudo npm install -g @openai/codex` 실행
4. 설치/업데이트 후 버전 출력

---

## 빠른 시작 (OpenAI 직접 접속)

```bash
# 1. Codex CLI 설치
bash codex-cli-setup/03-update-codex.sh

# 2. 원격 서버에서 ChatGPT 계정 로그인
codex login --device-auth

# 3. 계정에 GPT-6 Astra가 제공되는 경우 모델 지정 실행
codex --model gpt-6-astra
```

API 키 로그인, Bedrock API 키 입력 및 `bedrock-astra` 프로필 작성은 [README](../README.md)의 해당 절차를 사용합니다.
MCP 서버는 필요한 경우 위 명령으로 별도 등록합니다.
