#!/bin/bash

# Claude Code + Amazon Bedrock bashrc 설정 스크립트

BASHRC_FILE="$HOME/.bashrc"

echo "=== Claude Code + Amazon Bedrock bashrc 설정 ==="
echo

# ANTHROPIC_API_KEY 값 입력받기
read -p "ANTHROPIC_API_KEY 값을 입력하세요: " ANTHROPIC_KEY

if [ -z "$ANTHROPIC_KEY" ]; then
    echo "오류: ANTHROPIC_API_KEY 값이 비어있습니다."
    exit 1
fi

# AWS_BEARER_TOKEN_BEDROCK 값 입력받기
read -p "AWS_BEARER_TOKEN_BEDROCK 값을 입력하세요: " AWS_TOKEN

if [ -z "$AWS_TOKEN" ]; then
    echo "오류: AWS_BEARER_TOKEN_BEDROCK 값이 비어있습니다."
    exit 1
fi

# 기존 설정 확인
if grep -q "# Claude Code + Amazon Bedrock 설정" "$BASHRC_FILE" 2>/dev/null; then
    echo "기존 Claude Code + Bedrock 설정이 발견되었습니다."
    read -p "기존 설정을 덮어쓰시겠습니까? (y/n): " OVERWRITE
    if [ "$OVERWRITE" = "y" ] || [ "$OVERWRITE" = "Y" ]; then
        # 기존 설정 제거
        sed -i '/# Claude Code + Amazon Bedrock 설정/,/^$/d' "$BASHRC_FILE"
        echo "기존 설정을 제거했습니다."
    else
        echo "설정을 취소합니다."
        exit 0
    fi
fi

# bashrc에 설정 추가
cat >> "$BASHRC_FILE" << EOF

# Claude Code + Amazon Bedrock 설정
export ANTHROPIC_API_KEY="${ANTHROPIC_KEY}"
export AWS_BEARER_TOKEN_BEDROCK='${AWS_TOKEN}'
export CLAUDE_CODE_USE_BEDROCK=1
export ANTHROPIC_MODEL='global.anthropic.claude-opus-4-5-20251101-v1:0'
#export ANTHROPIC_MODEL='global.anthropic.claude-sonnet-4-5-20250929-v1:0'
export ANTHROPIC_SMALL_FAST_MODEL='us.anthropic.claude-haiku-4-5-20251001-v1:0'
export CLAUDE_CODE_MAX_OUTPUT_TOKENS=4096

EOF

echo
echo "bashrc에 설정이 추가되었습니다."
echo "설정을 적용하려면 다음 명령어를 실행하세요:"
echo "  source ~/.bashrc"
