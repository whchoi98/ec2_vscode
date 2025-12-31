#!/bin/bash

# Claude Code for VS Code Extension 설정 스크립트

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "====================================="
echo " Claude Code for VS Code 설정 스크립트"
echo "====================================="
echo ""

# OS 감지 및 설정 경로 결정
detect_os_and_path() {
    case "$(uname -s)" in
        Linux*)
            SETTINGS_DIR="$HOME/.config/Code/User"
            OS_NAME="Linux"
            ;;
        Darwin*)
            SETTINGS_DIR="$HOME/Library/Application Support/Code/User"
            OS_NAME="macOS"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            SETTINGS_DIR="$APPDATA/Code/User"
            OS_NAME="Windows"
            ;;
        *)
            echo "지원하지 않는 운영체제입니다."
            exit 1
            ;;
    esac
}

detect_os_and_path

echo -e "${BLUE}감지된 OS: ${OS_NAME}${NC}"
echo -e "${BLUE}설정 경로: ${SETTINGS_DIR}${NC}"
echo ""

# AWS Bearer Token 입력 받기
read -p "AWS_BEARER_TOKEN_BEDROCK 값을 입력하세요: " AWS_TOKEN

# 디렉토리 생성 (없는 경우)
mkdir -p "$SETTINGS_DIR"

# 기존 settings.json 백업 (있는 경우)
if [ -f "$SETTINGS_DIR/settings.json" ]; then
    BACKUP_FILE="$SETTINGS_DIR/settings.json.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$SETTINGS_DIR/settings.json" "$BACKUP_FILE"
    echo ""
    echo -e "${YELLOW}기존 설정 파일 백업됨: ${BACKUP_FILE}${NC}"
fi

# settings.json 파일 생성
cat > "$SETTINGS_DIR/settings.json" << EOF
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
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN} 설정 파일이 생성되었습니다!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo "경로: $SETTINGS_DIR/settings.json"
echo ""
echo "====================================="
echo -e "${YELLOW}설정을 적용하려면:${NC}"
echo ""
echo "  1. VS Code를 완전히 종료합니다"
echo "  2. VS Code를 다시 실행합니다"
echo ""
echo -e "${YELLOW}또는 VS Code 내에서:${NC}"
echo "  - Command Palette (Ctrl+Shift+P / Cmd+Shift+P) 열기"
echo "  - 'Developer: Reload Window' 실행"
echo ""
echo "====================================="
