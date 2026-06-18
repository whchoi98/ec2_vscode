#!/bin/bash

# Claude Code + Amazon Bedrock 셸 설정 스크립트 (Linux / macOS 공용)

# OS 감지 및 셸 RC 파일 결정
if [[ "$(uname)" == "Darwin" ]]; then
    # macOS: 기본 셸이 zsh (Catalina 이후)
    if [[ "$SHELL" == */zsh ]]; then
        SHELL_RC="$HOME/.zshrc"
    else
        SHELL_RC="$HOME/.bash_profile"
    fi
    OS_TYPE="macOS"
else
    SHELL_RC="$HOME/.bashrc"
    OS_TYPE="Linux"
fi

echo "=== Claude Code + Amazon Bedrock 셸 설정 ==="
echo "  대상 OS: $OS_TYPE"
echo "  설정 파일: $SHELL_RC"
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

# ANTHROPIC_MODEL 선택
echo
echo "사용할 모델을 선택하세요:"
echo "  1) Opus 4.8    (global.anthropic.claude-opus-4-8)"
echo "  2) Opus 4.7    (global.anthropic.claude-opus-4-7)"
echo "  3) Opus 4.6    (global.anthropic.claude-opus-4-6-v1)"
echo "  4) Sonnet 4.6  (global.anthropic.claude-sonnet-4-6)"
echo
read -p "선택 (1, 2, 3 또는 4, 기본값: 1): " MODEL_CHOICE

case "$MODEL_CHOICE" in
    2)
        SELECTED_MODEL="global.anthropic.claude-opus-4-7"
        echo "선택된 모델: Opus 4.7"
        ;;
    3)
        SELECTED_MODEL="global.anthropic.claude-opus-4-6-v1"
        echo "선택된 모델: Opus 4.6"
        ;;
    4)
        SELECTED_MODEL="global.anthropic.claude-sonnet-4-6"
        echo "선택된 모델: Sonnet 4.6"
        ;;
    *)
        SELECTED_MODEL="global.anthropic.claude-opus-4-8"
        echo "선택된 모델: Opus 4.8"
        ;;
esac

# CLAUDE_CODE_MAX_OUTPUT_TOKENS 선택
echo
echo "Max Output Tokens를 선택하세요:"
echo "  1) 4096  (간단한 질의응답)"
echo "  2) 16384 (일반적인 개발 작업)"
echo "  3) 32768 (큰 파일 생성 및 리팩토링)"
echo
read -p "선택 (1, 2 또는 3, 기본값: 2): " TOKEN_CHOICE

case "$TOKEN_CHOICE" in
    1)
        SELECTED_TOKENS=4096
        echo "선택된 Max Output Tokens: 4096"
        ;;
    3)
        SELECTED_TOKENS=32768
        echo "선택된 Max Output Tokens: 32768"
        ;;
    *)
        SELECTED_TOKENS=16384
        echo "선택된 Max Output Tokens: 16384"
        ;;
esac

# 기존 설정 확인
if grep -q "# Claude Code + Amazon Bedrock 설정" "$SHELL_RC" 2>/dev/null; then
    echo "기존 Claude Code + Bedrock 설정이 발견되었습니다."
    read -p "기존 설정을 덮어쓰시겠습니까? (y/n): " OVERWRITE
    if [ "$OVERWRITE" = "y" ] || [ "$OVERWRITE" = "Y" ]; then
        # 기존 설정 제거 (macOS BSD sed와 GNU sed 호환)
        if [[ "$(uname)" == "Darwin" ]]; then
            sed -i '' '/# Claude Code + Amazon Bedrock 설정/,/^$/d' "$SHELL_RC"
        else
            sed -i '/# Claude Code + Amazon Bedrock 설정/,/^$/d' "$SHELL_RC"
        fi
        echo "기존 설정을 제거했습니다."
    else
        echo "설정을 취소합니다."
        exit 0
    fi
fi

# bashrc에 설정 추가
cat >> "$SHELL_RC" << EOF

# Claude Code + Amazon Bedrock 설정
export ANTHROPIC_API_KEY="${ANTHROPIC_KEY}"
export AWS_BEARER_TOKEN_BEDROCK='${AWS_TOKEN}'
export CLAUDE_CODE_USE_BEDROCK=1
export ANTHROPIC_MODEL='${SELECTED_MODEL}'
export ANTHROPIC_DEFAULT_OPUS_MODEL='global.anthropic.claude-opus-4-8'
export ANTHROPIC_DEFAULT_SONNET_MODEL='global.anthropic.claude-sonnet-4-6'
export ANTHROPIC_DEFAULT_HAIKU_MODEL='global.anthropic.claude-haiku-4-5-20251001-v1:0'
export ANTHROPIC_SMALL_FAST_MODEL='us.anthropic.claude-haiku-4-5-20251001-v1:0'
export CLAUDE_CODE_MAX_OUTPUT_TOKENS=${SELECTED_TOKENS}
export ENABLE_PROMPT_CACHING_1H=1

EOF

echo
echo "bashrc에 설정이 추가되었습니다."
echo "설정을 적용하려면 다음 명령어를 실행하세요:"
echo "  source $SHELL_RC"
