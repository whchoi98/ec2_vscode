#!/bin/bash

# Claude Code VS Code Server 설정 스크립트

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "====================================="
echo " Claude Code 설정 스크립트"
echo "====================================="
echo ""

# AWS Bearer Token 입력 받기
read -p "AWS_BEARER_TOKEN_BEDROCK 값을 입력하세요: " AWS_TOKEN

# 디렉토리 생성 (없는 경우)
mkdir -p /home/ec2-user/.local/share/code-server/User

# settings.json 파일 생성
cat > /home/ec2-user/.local/share/code-server/User/settings.json << EOF
{
    "claudeCode.environmentVariables": [
    {
        "name": "CLAUDE_CODE_USE_BEDROCK",
        "value": "1"
    },
    {
      "name": "CLAUDE_CODE_SKIP_AUTH_LOGIN",
      "value": "true"
    },
    {
        "name": "AWS_BEARER_TOKEN_BEDROCK",
        "value": "${AWS_TOKEN}"
    },
    {
      "name": "AWS_REGION",
      "value": "us-east-1"
    },
    {
        "name": "ANTHROPIC_MODEL",
        "value": "global.anthropic.claude-opus-4-5-20251101-v1:0"
    },
    {
      "name": "ANTHROPIC_SMALL_FAST_MODEL",
      "value": "us.anthropic.claude-haiku-4-5-20251001-v1:0"
    },
    {
      "name" : "CLAUDE_CODE_SUBAGENT_MODEL",
      "value": "global.anthropic.claude-opus-4-5-20251101-v1:0"
    },
    {
      "name" : "MAX_THINKING_TOKENS",
      "value" : "1024"
    },
    {
      "name" : "CLAUDE_CODE_MAX_OUTPUT_TOKENS",
      "value" : "4096"
    }
    ],
    "claudeCode.disableLoginPrompt": true,
    "claudeCode.preferredLocation": "panel",
    "claudeCode.selectedModel": "global.anthropic.claude-opus-4-5-20251101-v1:0"
}
EOF

echo ""
echo -e "${GREEN}설정 파일이 생성되었습니다.${NC}"
echo "경로: /home/ec2-user/.local/share/code-server/User/settings.json"
echo ""
echo "====================================="
echo -e "${YELLOW}설정을 적용하려면 다음 명령어를 실행하세요:${NC}"
echo ""
echo "  sudo systemctl restart code-server"
echo ""
echo "====================================="
