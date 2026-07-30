# Kiro CLI Setup Scripts

VSCode Server 내에서 Kiro CLI 환경을 구성하는 스크립트 모음입니다.

## 사전 요구사항

| 항목 | 설치 확인 | 설치 방법 |
|------|----------|-----------|
| Kiro CLI | `kiro-cli --version` | UserData에서 자동 설치됨 |
| uv / uvx | `uvx --version` | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| AWS CLI | `aws --version` | UserData에서 자동 설치됨 |
| jq | `jq --version` | `sudo dnf install -y jq` |

## 스크립트 실행 순서

```
01-setup-auth.sh               브라우저/디바이스 플로우 인증
        |
        v
02-setup-model.sh              기본 모델 선택
        |
        v
03-setup-mcp-servers.sh        MCP 서버 설정 (~/.kiro/settings/mcp.json)
        |
        v
04-update-kiro.sh              Kiro CLI 업데이트 (수시)
        |
        v
05-install-skills.sh           Kiro CLI 스킬 설치 (선택)
```

---

## 01-setup-auth.sh

Kiro CLI 인증을 진행합니다. Kiro CLI는 **브라우저 기반 인증**을 사용하며, Bedrock 베어러 토큰 환경변수를 사용하지 않습니다.

**실행:**
```bash
bash kiro-cli-setup/01-setup-auth.sh
```

**지원되는 인증 방법:**
- GitHub
- Google
- AWS Builder ID
- AWS IAM Identity Center (엔터프라이즈)
- 외부 IdP (Okta, Microsoft Entra ID 등)

**원격 서버(SSH)에서 실행 시:**

브라우저를 열 수 없는 환경에서는 디바이스 플로우를 사용합니다.

```bash
kiro-cli login --use-device-flow
```

- `Select login method` → 사용하는 방식 선택 (예: Use with Your Organization)
- `Enter Start URL` → IAM Identity Center Start URL 입력 (예: `https://d-xxxxxxxxxx.awsapps.com/start`)
- `Enter Region` → 리전 입력 (예: `us-east-1`)
- 표시된 URL과 코드를 브라우저에서 입력하면 `Logged in successfully` 출력

---

## 02-setup-model.sh

기본 모델을 선택하여 `chat.defaultModel` 설정에 저장합니다.

**실행:**
```bash
bash kiro-cli-setup/02-setup-model.sh
```

**선택 가능한 모델 (기본값: `auto`):**

| 분류 | 모델 예시 |
|------|-----------|
| Auto | `auto` (작업별 최적 모델 자동 선택) |
| Claude Opus | `claude-opus-4.6`, `claude-opus-4.6-1m`, `claude-opus-4.5` |
| Claude Sonnet | `claude-sonnet-4.6`, `claude-sonnet-4.6-1m`, `claude-sonnet-4.5`, `claude-sonnet-4` |
| Claude Haiku | `claude-haiku-4.5` |
| Third-Party | `deepseek-3.2`, `kimi-k2.5`, `minimax-m2.5`, `glm-5`, `qwen3-coder-next` 등 |

**모델 변경 (대화 중):**
```bash
/model                          # 대화 중 모델 변경
/model set-current-as-default   # 현재 모델을 기본값으로 저장
```

---

## 03-setup-mcp-servers.sh

`~/.kiro/settings/mcp.json`에 AWS MCP 서버를 등록합니다.

**실행:**
```bash
bash kiro-cli-setup/03-setup-mcp-servers.sh
```

**등록되는 MCP 서버 (2개):**

| 서버 | 패키지 | 기능 |
|------|--------|------|
| awslabs-terraform-mcp-server | `awslabs.terraform-mcp-server` | Terraform/Terragrunt AWS 인프라 개발 |
| bedrock-agentcore-mcp-server | `awslabs.amazon-bedrock-agentcore-mcp-server` | Bedrock AgentCore Gateway, Memory, Runtime |

> **Note:** AWS API, Cost Explorer, Pricing, Diagram 도구는 Kiro CLI에 빌트인되어 있어
> 별도 MCP 서버(`core-mcp-server`) 설치가 불필요합니다.

**설정 파일:**
```
~/.kiro/settings/mcp.json
```

기존 설정이 있으면 `.backup.<timestamp>`로 백업 후 `jq`로 병합합니다.

---

## 04-update-kiro.sh

Kiro CLI를 최신 버전으로 업데이트합니다. ARM64/x86_64 아키텍처를 자동 감지합니다.

**실행:**
```bash
bash kiro-cli-setup/04-update-kiro.sh
```

---

## 05-install-skills.sh

Kiro CLI 스킬을 설치합니다. 기본은 전역 설치(`~/.kiro/skills`)이며, `--local` 옵션으로 프로젝트 단위(`.kiro/skills`) 설치가 가능합니다.

**실행:**
```bash
# 전역 설치 (~/.kiro/skills)
bash kiro-cli-setup/05-install-skills.sh

# 프로젝트 단위 설치 (.kiro/skills)
bash kiro-cli-setup/05-install-skills.sh --local
```

**설치되는 스킬 (36개):** `aws-iac`, `aws-security`, `aws-cost`, `cloud-architect`, `code-review`, `refactor`, `terraform`, `strands`, `aws-agentcore` 등

**스킬 사용:**
```bash
kiro-cli chat --agent powers          # powers 에이전트로 채팅 시작
/agent powers                         # 채팅 중 powers 에이전트로 전환
/context show                         # 로드된 스킬 확인

kiro-cli settings chat.defaultAgent powers   # powers를 기본 에이전트로 지정
```

---

## 빠른 시작

```bash
# 1. 인증
bash kiro-cli-setup/01-setup-auth.sh
#    원격 서버(SSH)에서는: kiro-cli login --use-device-flow

# 2. 기본 모델 설정
bash kiro-cli-setup/02-setup-model.sh

# 3. MCP 서버 설정
bash kiro-cli-setup/03-setup-mcp-servers.sh

# 4. Kiro CLI 업데이트 (선택)
bash kiro-cli-setup/04-update-kiro.sh

# 5. Kiro CLI 스킬 설치 (선택)
bash kiro-cli-setup/05-install-skills.sh

# 6. Kiro CLI 실행
kiro-cli
```
