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

# 임시 파일 생성
TEMP_FILE=$(mktemp)
TEMP_EXISTING=$(mktemp)

# Claude Code 설정 JSON을 임시 파일에 저장
cat > "$TEMP_FILE" << EOF
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

# trailing comma 제거 함수 (VS Code JSON은 trailing comma를 허용하지만 jq는 허용하지 않음)
fix_json_trailing_comma() {
    # 줄바꿈을 임시 문자로 변환 후 ,} 또는 ,] 패턴 제거
    cat "$1" | tr '\n' '\r' | sed 's/,\r\s*}/\r}/g; s/,\r\s*]/\r]/g' | tr '\r' '\n'
}

# 기존 파일이 있으면 병합, 없으면 새로 생성
if [ -f "$SETTINGS_FILE" ] && [ -s "$SETTINGS_FILE" ]; then
    echo ""
    echo -e "${BLUE}기존 설정 파일에 Claude Code 설정을 추가합니다...${NC}"

    # trailing comma 제거 후 임시 파일에 저장
    fix_json_trailing_comma "$SETTINGS_FILE" > "$TEMP_EXISTING"

    # 기존 JSON과 새 설정 병합 (기존 설정 + 새 Claude Code 설정)
    MERGED_FILE=$(mktemp)

    if jq -s '.[0] * .[1]' "$TEMP_EXISTING" "$TEMP_FILE" > "$MERGED_FILE" 2>/dev/null; then
        # 병합 성공 - 결과를 원본 파일에 복사
        cp "$MERGED_FILE" "$SETTINGS_FILE"
        echo -e "${GREEN}기존 설정과 병합 완료${NC}"
    else
        echo -e "${RED}JSON 병합 실패. 기존 파일 형식을 확인하세요.${NC}"
        echo -e "${YELLOW}백업 파일에서 복원 가능: ${BACKUP_FILE}${NC}"
        rm -f "$TEMP_FILE" "$TEMP_EXISTING" "$MERGED_FILE"
        exit 1
    fi

    rm -f "$MERGED_FILE"
else
    echo ""
    echo -e "${BLUE}새 설정 파일을 생성합니다...${NC}"
    cp "$TEMP_FILE" "$SETTINGS_FILE"
fi

# 임시 파일 삭제
rm -f "$TEMP_FILE" "$TEMP_EXISTING"

# 결과 출력
echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN} 설정이 완료되었습니다!${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo "경로: $SETTINGS_FILE"
echo ""
echo -e "${BLUE}현재 설정 내용:${NC}"
echo "-------------------------------------"
cat "$SETTINGS_FILE"
echo ""
echo "-------------------------------------"
echo ""
echo "====================================="
echo -e "${YELLOW}설정을 적용하려면 다음 명령어를 실행하세요:${NC}"
echo ""
echo "  sudo systemctl restart code-server"
echo ""
echo "====================================="
