# Claude Code Setup Scripts

Amazon Bedrock 기반 Claude Code 환경을 구성하는 셸 스크립트 모음입니다.
Linux (EC2/Amazon Linux) 및 macOS 환경 모두 지원합니다.

## 사전 요구사항

| 항목 | 설치 확인 | 설치 방법 (Linux) | 설치 방법 (macOS) |
|------|----------|-------------------|-------------------|
| Claude Code CLI | `claude --version` | `npm install -g @anthropic-ai/claude-code` | `npm install -g @anthropic-ai/claude-code` |
| Node.js / npm | `node --version` | `sudo dnf install -y nodejs` | `brew install node` |
| uv / uvx | `uvx --version` | `curl -LsSf https://astral.sh/uv/install.sh \| sh` | `brew install uv` |
| AWS CLI | `aws --version` | [AWS CLI 설치 가이드](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) | `brew install awscli` |
| jq | `jq --version` | `sudo dnf install -y jq` (02번 스크립트에서 자동 설치) | `brew install jq` (02번 스크립트에서 자동 설치) |

### OS별 셸 설정 파일

| OS | 기본 셸 | 설정 파일 |
|----|---------|-----------|
| Linux (EC2) | bash | `~/.bashrc` |
| macOS (Catalina+) | zsh | `~/.zshrc` |
| macOS (레거시) | bash | `~/.bash_profile` |

> 모든 스크립트는 자동으로 OS를 감지하여 적절한 셸 설정 파일을 사용합니다.

## 스크립트 실행 순서

```
01-setup-bedrock-env.sh        Bedrock 환경변수 설정
        |
        v
   source ~/.bashrc             환경변수 적용
        |
        v
02-setup-vscode-settings.sh    VS Code 확장 설정 (code-server 사용 시)
        |
        v
03-setup-plugins-and-mcp.sh    플러그인 + MCP 서버 설치
        |
        v
04-update-claude.sh            Claude Code 업데이트 (수시)
        |
        v
05-setup-custom-plugin.sh      커스텀 플러그인 설치 (선택)
        |
        v
06-switch-mode.sh              모드 전환 (선택)
        |
        v
07-setup-aws-skills.sh         AWS Skills 36개 설치
        |
        v
   claude                       Claude Code 세션에서 /init-project 실행
```

---

## 01-setup-bedrock-env.sh

Amazon Bedrock 연동에 필요한 환경변수를 셸 설정 파일에 추가합니다.
- Linux: `~/.bashrc` / macOS (zsh): `~/.zshrc` / macOS (bash): `~/.bash_profile`

**실행:**
```bash
bash 01-setup-bedrock-env.sh
```

**대화형 입력 항목:**
- `ANTHROPIC_API_KEY` - Anthropic API 키
- `AWS_BEARER_TOKEN_BEDROCK` - AWS Bearer Token
- 모델 선택 (Opus 5 / Opus 4.8 / Opus 4.7 / Opus 4.6 / Sonnet 5 / Sonnet 4.6)
- Max Output Tokens 선택 (4096 / 16384 / 32768)

**설정되는 환경변수:**
```bash
ANTHROPIC_API_KEY
AWS_BEARER_TOKEN_BEDROCK
CLAUDE_CODE_USE_BEDROCK=1
ANTHROPIC_MODEL                    # 선택한 모델
ANTHROPIC_DEFAULT_OPUS_MODEL       # global.anthropic.claude-opus-5
ANTHROPIC_DEFAULT_SONNET_MODEL     # global.anthropic.claude-sonnet-5
ANTHROPIC_DEFAULT_HAIKU_MODEL      # global.anthropic.claude-haiku-4-5-20251001-v1:0
ANTHROPIC_SMALL_FAST_MODEL         # us.anthropic.claude-haiku-4-5-20251001-v1:0
CLAUDE_CODE_MAX_OUTPUT_TOKENS      # 선택한 토큰 수 (기본값: 16384)
ENABLE_PROMPT_CACHING_1H=1         # 1시간 prompt 캐싱 활성화
```

**실행 후 반드시:**
```bash
# Linux
source ~/.bashrc
# macOS (zsh)
source ~/.zshrc
```

---

## 02-setup-vscode-settings.sh

VS Code 확장의 `settings.json`을 설정합니다. (Linux code-server / macOS VS Code 자동 감지)

**실행:**
```bash
bash 02-setup-vscode-settings.sh
```

**대화형 입력 항목:**
- `AWS_BEARER_TOKEN_BEDROCK` - AWS Bearer Token

**동작:**
- 기존 `settings.json` 백업 (타임스탬프 포함)
- Claude Code 설정 JSON 생성
- 기존 파일이 있으면 `jq`로 병합, 없으면 새로 생성

**주요 설정값:**

| 설정 | 값 |
|------|-----|
| `ANTHROPIC_MODEL` | `global.anthropic.claude-opus-5` |
| `ANTHROPIC_SMALL_FAST_MODEL` | `us.anthropic.claude-haiku-4-5-20251001-v1:0` |
| `CLAUDE_CODE_SUBAGENT_MODEL` | `global.anthropic.claude-opus-5` |
| `MAX_THINKING_TOKENS` | `10240` |
| `CLAUDE_CODE_MAX_OUTPUT_TOKENS` | `16384` |
| `ENABLE_PROMPT_CACHING_1H` | `1` |

**설정 경로:**
```
Linux (code-server):  ~/.local/share/code-server/User/settings.json
macOS (VS Code):      ~/Library/Application Support/Code/User/settings.json
```

**설정 후:**
```bash
# Linux (code-server)
sudo systemctl restart code-server
# macOS
# VS Code를 재시작하세요.
```

---

## 03-setup-plugins-and-mcp.sh

Claude Code 플러그인과 AWS MCP 서버를 일괄 설치합니다.

**실행:**
```bash
bash 03-setup-plugins-and-mcp.sh
```

**설치 내용:**

플러그인 (claude-plugins-official, 27개):

| 카테고리 | 플러그인 |
|----------|---------|
| 개발 워크플로우 | commit-commands, code-review, code-simplifier, feature-dev, pr-review-toolkit, claude-md-management, plugin-dev, agent-sdk-dev, claude-code-setup |
| 프론트엔드 | frontend-design |
| LSP | pyright-lsp, typescript-lsp, gopls-lsp, jdtls-lsp |
| 외부 서비스 | context7, github, playwright, slack, stripe, linear, supabase, serena |
| 유틸리티 | ralph-loop, superpowers, qodo-skills, explanatory-output-style, security-guidance |

플러그인 (agent-plugins-for-aws, 1개):

| 플러그인 | 포함 MCP |
|---------|---------|
| deploy-on-aws | awsiac, awsknowledge, awspricing |

MCP 서버 (3개):

| 서버 | 패키지 | 기능 |
|------|--------|------|
| awslabs-terraform-mcp-server | `awslabs.terraform-mcp-server` | Terraform/Terragrunt AWS 인프라 개발 |
| awslabs-core-mcp-server | `awslabs.core-mcp-server` | AWS API, Cost Explorer, 다이어그램, 가격 분석 |
| bedrock-agentcore-mcp-server | `awslabs.amazon-bedrock-agentcore-mcp-server` | Bedrock AgentCore Gateway, Memory, Runtime |

---

## 04-update-claude.sh

Claude Code CLI를 최신 버전으로 업데이트합니다.

**실행:**
```bash
bash 04-update-claude.sh
```

**동작:**
1. 현재 버전 출력
2. `npm update -g @anthropic-ai/claude-code` 실행
3. 업데이트 후 버전 출력

---

## 05-setup-custom-plugin.sh

커스텀 플러그인(`project-init`)을 로컬 마켓플레이스에 등록하고 설치합니다.

> `../claude_code_plugin/` 디렉토리에 플러그인 소스가 있어야 합니다.

**실행:**
```bash
bash 05-setup-custom-plugin.sh
```

**동작:**
1. `../claude_code_plugin/` 소스 존재 확인
2. `~/custom-claude-plugins/` 에 로컬 마켓플레이스 생성 (이미 있으면 소스만 업데이트)
3. `claude plugin marketplace add`로 마켓플레이스 등록
4. `project-init@custom-claude-plugins` 설치

**설치되는 플러그인:**

| 플러그인 | 명령어 | 기능 |
|---------|--------|------|
| project-init | `/init-project` | 프로젝트 구조 초기화 (CLAUDE.md, docs, hooks, skills) |
|                     | `/sync-docs` | 전체 문서를 코드 상태와 동기화 |

> 이전의 `04-init-project.sh` (셸 스크립트로 빈 뼈대 생성)는 이 플러그인으로 대체되었습니다.
> 플러그인은 Claude가 대화를 통해 프로젝트 컨텍스트를 파악하고 내용까지 채워주는 방식으로 동작합니다.

---

## 06-switch-mode.sh

C4E (Enterprise) / 구독형 (Subscription) / Bedrock API 모드를 전환합니다.

**실행:**
```bash
bash 06-switch-mode.sh              # 대화형 전환
bash 06-switch-mode.sh status       # 현재 모드 확인
bash 06-switch-mode.sh c4e          # C4E로 즉시 전환
bash 06-switch-mode.sh subscription # 구독형으로 즉시 전환
bash 06-switch-mode.sh bedrock      # Bedrock으로 즉시 전환
bash 06-switch-mode.sh setup        # 전체 프로필 재설정
```

**동작 원리:**
- `~/.claude-env/c4e.env` — C4E (Enterprise) 프로필
- `~/.claude-env/subscription.env` — 구독형 프로필
- `~/.claude-env/bedrock.env` — Bedrock API 프로필
- `~/.claude-env/active.env` — 활성 프로필 (symlink)
- `~/.bashrc`에 `source ~/.claude-env/active.env` 자동 등록

**모드별 차이점:**

| 항목 | C4E (Enterprise) | 구독형 (Subscription) | Bedrock API |
|------|------------------|----------------------|-------------|
| 인증 방식 | OAuth/SSO (`claude login`) | API Key | API Key + Bearer Token |
| `ANTHROPIC_API_KEY` | (해제) | Anthropic API Key | Anthropic API Key |
| `CLAUDE_CODE_USE_BEDROCK` | (해제) | (해제) | `1` |
| `AWS_BEARER_TOKEN_BEDROCK` | (해제) | (해제) | AWS Bearer Token |
| `ANTHROPIC_MODEL` | (기본값 사용) | (기본값 사용) | `global.anthropic.claude-*` |
| 모델 ID 형식 | `claude-opus-5` 등 | `claude-opus-5` 등 | `global.anthropic.claude-opus-5` 등 |
| `ENABLE_PROMPT_CACHING_1H` | 자동 (설정 불필요) | `1` | `1` |

**전환 후 반드시:**
```bash
# Linux
source ~/.bashrc
# macOS (zsh)
source ~/.zshrc
```

> C4E 모드 전환 후 로그인이 필요하면: `claude login`
> 기존 `01-setup-bedrock-env.sh`로 설정한 환경변수는 자동으로 비활성화(주석 처리)됩니다.

---

## 07-setup-aws-skills.sh

[aws-skills-for-claude-code](https://github.com/whchoi98/aws-skills-for-claude-code) 리포지토리에서 36개 AWS 스킬을 설치합니다.

**실행:**
```bash
bash 07-setup-aws-skills.sh
```

**동작:**
1. 리포지토리를 `~/.claude/aws-skills-for-claude-code/`에 클론 (이미 있으면 `git pull`)
2. `.kiro/skills/` 내 36개 SKILL.md를 `~/.claude/skills/`로 복사
3. 재실행 시 최신 버전으로 자동 업데이트

**설치되는 스킬 (36개):**

| 카테고리 | 스킬 |
|----------|------|
| AWS 서비스 (16) | aws-agentcore, aws-amplify, aws-cloudwatch, aws-cost, aws-data, aws-healthomics, aws-iac, aws-iam, aws-infra, aws-messaging, aws-sam, aws-security, cloud-architect, cloudwatch-appsignals, saas-builder, strands |
| 마이그레이션 (5) | arm-soc-migration, aws-graviton-migration, aws-mcp, aws-observability, gcp-aws-migrate |
| 외부 서비스 (9) | checkout, datadog, dynatrace, figma, neon, postman, stackgen, stripe, terraform |
| 개발 워크플로우 (6) | code-review, power-builder, refactor, release, spark-troubleshooting, sync-docs |

**사용법:**
```bash
# 수동 호출
/aws-cloudwatch
/terraform

# 또는 대화에서 키워드 언급 시 자동 활성화
```

---

## 08-setup-claude-hud.sh

[claude-hud](https://github.com/jarrodwatts/claude-hud) 플러그인을 설치하고 statusLine HUD를 구성합니다. 대화형 `/claude-hud:setup`이 수행하는 작업을 비대화형으로 재현합니다.

**실행:**
```bash
bash 08-setup-claude-hud.sh
```

**동작:**
1. `jarrodwatts/claude-hud` 마켓플레이스 등록 + `claude-hud` 플러그인 설치
2. 런타임(bun 우선, node 폴백) 자동 감지 — bun은 `src/index.ts`, node는 `dist/index.js`
3. `~/.claude/settings.json`에 statusLine 명령 기록 (기존 설정 보존 + 타임스탬프 백업)
4. `~/.claude/plugins/claude-hud/config.json`에 확장 표시 기능 활성화
5. 생성 명령 실행 테스트로 검증

**활성화되는 확장 기능:**

| 기능 | config 키 |
|------|-----------|
| Tools activity | `display.showTools` |
| Agents & Todos | `display.showAgents`, `display.showTodos` |
| Session info | `display.showDuration`, `display.showConfigCounts` |
| Session name | `display.showSessionName` |

> statusLine 명령은 실행 시점에 최신 설치 버전을 동적 탐색하므로, 플러그인 업데이트 후 재실행이 불필요합니다.
> 설정 적용에는 **Claude Code 재시작**이 필요합니다.

---

## 빠른 시작 (전체 흐름)

```bash
# 1. Bedrock 환경변수 설정
bash 01-setup-bedrock-env.sh
source ~/.bashrc

# 2. VS Code 확장 설정 (code-server 사용 시)
bash 02-setup-vscode-settings.sh

# 3. 플러그인 + MCP 서버 설치
bash 03-setup-plugins-and-mcp.sh

# 4. Claude Code 업데이트 (선택)
bash 04-update-claude.sh

# 5. 커스텀 플러그인 설치
bash 05-setup-custom-plugin.sh

# 6. 구독형 ↔ Bedrock 모드 전환 (필요 시)
bash 06-switch-mode.sh

# 7. AWS Skills 36개 설치
bash 07-setup-aws-skills.sh

# 8. claude-hud statusLine HUD 설치/설정 (선택)
bash 08-setup-claude-hud.sh

# 9. Claude Code 세션에서 프로젝트 초기화
claude
# 세션 내에서: /init-project ./my-project
```
