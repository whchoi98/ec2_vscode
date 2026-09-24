#!/bin/bash

# Codex CLI 환경변수 bashrc 설정 스크립트

BASHRC_FILE="$HOME/.bashrc"

echo "=== Codex CLI 환경변수 설정 ==="
echo

# Provider 선택
echo "API Provider를 선택하세요:"
echo "  1) OpenAI API (OPENAI_API_KEY)"
echo "  2) Amazon Bedrock (Bedrock 엔드포인트 + Bedrock API 키)"
echo "  3) 기타 OpenAI-compatible (커스텀 Base URL)"
echo
read -p "선택 (1-3, 기본값: 1): " PROVIDER_CHOICE

case "$PROVIDER_CHOICE" in
    2)
        PROVIDER="bedrock"
        echo "선택: Amazon Bedrock"
        ;;
    3)
        PROVIDER="custom"
        echo "선택: 커스텀 Provider"
        ;;
    *)
        PROVIDER="openai"
        echo "선택: OpenAI API"
        ;;
esac

echo

# Provider별 설정
# OPENAI_API_KEY는 공통 환경변수 이름이며, 선택한 Provider에서 발급한 키를 저장합니다.
if [ "$PROVIDER" = "openai" ]; then
    read -r -s -p "OpenAI Platform에서 발급한 API 키 (필수, 입력 내용 숨김): " API_KEY
    echo
    if [ -z "$API_KEY" ]; then
        echo "오류: OpenAI API 키가 비어있습니다."
        exit 1
    fi

elif [ "$PROVIDER" = "bedrock" ]; then
    read -r -p "OPENAI_BASE_URL (Bedrock 엔드포인트 URL)을 입력하세요: " BASE_URL
    if [ -z "$BASE_URL" ]; then
        echo "오류: OPENAI_BASE_URL 값이 비어있습니다."
        exit 1
    fi
    echo "OPENAI_API_KEY는 환경변수 이름이며, 이 모드에서는 Amazon Bedrock API 키를 저장합니다."
    read -r -s -p "Amazon Bedrock에서 발급한 API 키 (필수, 입력 내용 숨김): " API_KEY
    echo
    if [ -z "$API_KEY" ]; then
        echo "오류: Amazon Bedrock API 키가 비어있습니다."
        exit 1
    fi

elif [ "$PROVIDER" = "custom" ]; then
    read -r -p "OPENAI_BASE_URL (커스텀 Provider 엔드포인트 URL)을 입력하세요: " BASE_URL
    if [ -z "$BASE_URL" ]; then
        echo "오류: OPENAI_BASE_URL 값이 비어있습니다."
        exit 1
    fi
    read -r -s -p "커스텀 Provider에서 발급한 API 키 (필수, 입력 내용 숨김): " API_KEY
    echo
    if [ -z "$API_KEY" ]; then
        echo "오류: 커스텀 Provider API 키가 비어있습니다."
        exit 1
    fi
fi

# 모델 선택
echo
echo "사용할 모델을 선택하세요:"
echo "  1) gpt-5.3-codex      (기본값) Latest frontier agentic coding model"
echo "  2) gpt-5.4                     Latest frontier agentic coding model"
echo "  3) gpt-5.2-codex               Frontier agentic coding model"
echo "  4) gpt-5.1-codex-max           Codex-optimized flagship for deep and fast reasoning"
echo "  5) gpt-5.2                     Latest frontier model with improvements across knowledge, reasoning and coding"
echo "  6) gpt-5.1-codex-mini          Optimized for codex. Cheaper, faster, but less capable"
echo "  7) 직접 입력"
echo
read -p "선택 (1-7, 기본값: 1): " MODEL_CHOICE

case "$MODEL_CHOICE" in
    2) SELECTED_MODEL="gpt-5.4" ;;
    3) SELECTED_MODEL="gpt-5.2-codex" ;;
    4) SELECTED_MODEL="gpt-5.1-codex-max" ;;
    5) SELECTED_MODEL="gpt-5.2" ;;
    6) SELECTED_MODEL="gpt-5.1-codex-mini" ;;
    7)
        read -p "모델 ID를 입력하세요: " SELECTED_MODEL
        if [ -z "$SELECTED_MODEL" ]; then
            echo "오류: 모델 ID가 비어있습니다."
            exit 1
        fi
        ;;
    *) SELECTED_MODEL="gpt-5.3-codex" ;;
esac
echo "선택된 모델: $SELECTED_MODEL"

# 기존 설정 확인
if grep -q "# Codex CLI 환경변수 설정" "$BASHRC_FILE" 2>/dev/null; then
    echo
    echo "기존 Codex CLI 설정이 발견되었습니다."
    read -p "기존 설정을 덮어쓰시겠습니까? (y/n): " OVERWRITE
    if [ "$OVERWRITE" = "y" ] || [ "$OVERWRITE" = "Y" ]; then
        sed -i '/# Codex CLI 환경변수 설정/,/^$/d' "$BASHRC_FILE"
        echo "기존 설정을 제거했습니다."
    else
        echo "설정을 취소합니다."
        exit 0
    fi
fi

# bashrc에 설정 추가
{
    echo ""
    echo "# Codex CLI 환경변수 설정"

    if [ -n "${API_KEY:-}" ]; then
        echo "export OPENAI_API_KEY='${API_KEY}'"
    fi

    if [ -n "${BASE_URL:-}" ]; then
        echo "export OPENAI_BASE_URL='${BASE_URL}'"
    fi

    echo "export CODEX_DEFAULT_MODEL='${SELECTED_MODEL}'"
    echo ""
} >> "$BASHRC_FILE"

echo
echo "bashrc에 설정이 추가되었습니다."
echo
echo "  Provider: $PROVIDER"
echo "  Model:    $SELECTED_MODEL"
echo
echo "설정을 적용하려면 다음 명령어를 실행하세요:"
echo "  source ~/.bashrc"
