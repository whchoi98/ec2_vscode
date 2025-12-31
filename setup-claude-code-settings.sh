#!/bin/bash

# Claude Code for VS Code Extension (EC2 code-server) 설정 스크립트

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# code-server 설정 경로
SETTINGS_DIR="/home/ec2-user/.local/share/code-server/User"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"

echo "====================================="
echo " Claude Code for VS Code 설정 스크립트"
echo " (EC2 code-server 환경)"
echo "====================================="
echo ""
echo -e "${BLUE}설정 경로: ${SETTINGS_FILE}${NC}"
echo ""

# jq 설치 확인
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}jq가 설치되어 있지 않습니다. 설치 중...${NC}"
    sudo yum install -y jq || sudo apt-get install -y jq
fi

# AWS Bearer Token 입력 받기
read -p "AWS_BEARER_TOKEN_BEDROCK 값을 입력하세요: " AWS_TOKEN

# 디렉토리 생성 (없는 경우)
mkdir -p "$SETTINGS_DIR"

# 기존 settings.json 백업 (있는 경우)
if [ -f "$SETTINGS_FILE" ]; then
    BACKUP_FILE="$SETTINGS_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$SETTINGS_FILE" "$BACKUP_FILE"
    echo ""
    echo -e "${YELLOW}기존 설정 파일 백업됨: ${BACKUP_FILE}${NC}"
fi

# Claude Code 설정 JSON
CLAUDE_CODE_SETTINGS=$(cat << EOF
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
)

# 기존 파일이 있으면 병합, 없으면 새로 생성
if [ -f "$SETTINGS_FILE" ] && [ -s "$SETTINGS_FILE" ]; then
    echo ""
    echo -e "${BLUE}기존 설정 파일에 Claude Code 설정을 추가합니다...${NC}"

    # 기존 JSON과 새 설정 병합 (새 설정이 우선)
    MERGED=$(jq -s '.[0] * .[1]' "$SETTINGS_FILE" <(echo "$CLAUDE_CODE_SETTINGS"))

    if [ $? -eq 0 ]; then
        echo "$MERGED" > "$SETTINGS_FILE"
    else
        echo -e "${RED}JSON 병합 실패. 새 설정 파일로 생성합니다.${NC}"
        echo "$CLAUDE_CODE_SETTINGS" | jq '.' > "$SETTINGS_FILE"
    fi
else
    echo ""
    echo -e "${BLUE}새 설정 파일을 생성합니다...${NC}"
    echo "$CLAUDE_CODE_SETTINGS" | jq '.' > "$SETTINGS_FILE"
fi

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN} 설정이 완료되었습니다!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo "경로: $SETTINGS_FILE"
echo ""
echo "====================================="
echo -e "${YELLOW}설정을 적용하려면 다음 명령어를 실행하세요:${NC}"
echo ""
echo "  sudo systemctl restart code-server"
echo ""
echo "====================================="
