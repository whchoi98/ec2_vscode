#!/bin/bash
###############################################################################
#
#   Claude Code 모드 전환 스크립트
#   Switch between C4E / Subscription (Pro/Max) / Bedrock API mode
#
#   프로필 저장 경로: ~/.claude-env/
#       c4e.env            - C4E (Claude for Enterprise, OAuth)
#       subscription.env   - 구독형 (Anthropic 직접, API Key)
#       bedrock.env        - Bedrock API
#       active.env         -> 현재 활성 프로필 (symlink)
#
#   사용법:
#       bash 06-switch-mode.sh              대화형 전환
#       bash 06-switch-mode.sh status       현재 모드 확인
#       bash 06-switch-mode.sh c4e          C4E 모드로 전환
#       bash 06-switch-mode.sh subscription 구독형으로 전환
#       bash 06-switch-mode.sh bedrock      Bedrock으로 전환
#       bash 06-switch-mode.sh setup        전체 프로필 재설정
#
###############################################################################

set -euo pipefail

# -- 색상 / Colors -----------------------------------------------------------
GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'
YELLOW='\033[1;33m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

ENV_DIR="$HOME/.claude-env"
C4E_ENV="$ENV_DIR/c4e.env"
SUB_ENV="$ENV_DIR/subscription.env"
BRK_ENV="$ENV_DIR/bedrock.env"
ACTIVE_ENV="$ENV_DIR/active.env"

# OS 감지 및 셸 RC 파일 결정
if [[ "$(uname)" == "Darwin" ]]; then
    if [[ "$SHELL" == */zsh ]]; then
        SHELL_RC="$HOME/.zshrc"
    else
        SHELL_RC="$HOME/.bash_profile"
    fi
else
    SHELL_RC="$HOME/.bashrc"
fi

BASHRC="$SHELL_RC"
BASHRC_MARKER="# Claude Code Mode (managed by 06-switch-mode.sh)"

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

###############################################################################
# 현재 모드 감지
###############################################################################
get_current_mode() {
    if [ -L "$ACTIVE_ENV" ]; then
        local target
        target=$(readlink "$ACTIVE_ENV")
        case "$target" in
            *c4e.env)          echo "c4e" ;;
            *subscription.env) echo "subscription" ;;
            *bedrock.env)      echo "bedrock" ;;
            *)                 echo "unknown" ;;
        esac
    elif [ -f "$ACTIVE_ENV" ]; then
        if grep -q "CLAUDE_CODE_USE_BEDROCK=1" "$ACTIVE_ENV" 2>/dev/null; then
            echo "bedrock"
        elif grep -q "ANTHROPIC_API_KEY" "$ACTIVE_ENV" 2>/dev/null; then
            echo "subscription"
        else
            echo "c4e"
        fi
    else
        echo "none"
    fi
}

# 모드 이름 한글 표시
mode_label() {
    case "$1" in
        c4e)          echo "C4E (Enterprise, OAuth)" ;;
        subscription) echo "구독형 (Subscription)" ;;
        bedrock)      echo "Bedrock API" ;;
        none)         echo "미설정 (Not configured)" ;;
        *)            echo "알 수 없음 (Unknown)" ;;
    esac
}

# 모드 색상
mode_color() {
    case "$1" in
        c4e)          echo "$GREEN" ;;
        subscription) echo "$CYAN" ;;
        bedrock)      echo "$YELLOW" ;;
        *)            echo "$RED" ;;
    esac
}

###############################################################################
# 상태 표시
###############################################################################
show_status() {
    local mode
    mode=$(get_current_mode)
    local color
    color=$(mode_color "$mode")

    echo ""
    echo -e "${BOLD}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}│  Claude Code 모드 상태 / Mode Status              │${NC}"
    echo -e "${BOLD}├──────────────────────────────────────────────────┤${NC}"
    echo -e "│  현재 모드: ${color}${BOLD}$(mode_label "$mode")${NC}"
    echo -e "│                                                  │"

    # 프로필 파일 존재 여부
    local check mark_ok mark_no
    mark_ok="${GREEN}✓ 설정됨${NC}"
    mark_no="${DIM}─ 미설정${NC}"

    echo -e "│  C4E 프로필:      $([ -f "$C4E_ENV" ] && echo "$mark_ok" || echo "$mark_no")"
    echo -e "│  구독형 프로필:   $([ -f "$SUB_ENV" ] && echo "$mark_ok" || echo "$mark_no")"
    echo -e "│  Bedrock 프로필:  $([ -f "$BRK_ENV" ] && echo "$mark_ok" || echo "$mark_no")"

    echo -e "${BOLD}└──────────────────────────────────────────────────┘${NC}"
    echo ""
}

###############################################################################
# Max Output Tokens 선택 (공통)
###############################################################################
choose_max_tokens() {
    echo "" >&2
    echo "  Max Output Tokens:" >&2
    echo "    1) 16384 (기본값 / 일반 개발)" >&2
    echo "    2) 32768 (대규모 코드 생성)" >&2
    echo "    3) 4096  (간단한 질의응답)" >&2
    read -p "  선택 [1]: " TOKEN_CHOICE
    TOKEN_CHOICE="${TOKEN_CHOICE:-1}"

    case "$TOKEN_CHOICE" in
        2) echo 32768 ;;
        3) echo 4096 ;;
        *) echo 16384 ;;
    esac
}

###############################################################################
# Anthropic API 모델 선택 (C4E / Subscription 공통)
###############################################################################
choose_anthropic_model() {
    echo "" >&2
    echo "  기본 모델 선택:" >&2
    echo "    1) Opus 4.8   (claude-opus-4-8) (기본값)" >&2
    echo "    2) Opus 4.7   (claude-opus-4-7)" >&2
    echo "    3) Opus 4.6   (claude-opus-4-6)" >&2
    echo "    4) Sonnet 4.6 (claude-sonnet-4-6)" >&2
    read -p "  선택 [1]: " MODEL_CHOICE
    MODEL_CHOICE="${MODEL_CHOICE:-1}"

    case "$MODEL_CHOICE" in
        2) echo "claude-opus-4-7" ;;
        3) echo "claude-opus-4-6" ;;
        4) echo "claude-sonnet-4-6" ;;
        *) echo "claude-opus-4-8" ;;
    esac
}

###############################################################################
# C4E (Enterprise) 프로필 설정
###############################################################################
setup_c4e() {
    echo ""
    echo -e "${CYAN}=== C4E (Claude for Enterprise) 프로필 설정 ===${NC}"
    echo ""
    echo -e "${DIM}  Enterprise 구독 사용자용 (OAuth/SSO 인증)${NC}"
    echo -e "${DIM}  별도의 API Key 없이 'claude login'으로 인증${NC}"
    echo ""

    local model
    model=$(choose_anthropic_model)

    local max_tokens
    max_tokens=$(choose_max_tokens)

    # 프로필 파일 생성
    cat > "$C4E_ENV" << EOF
# Claude Code - C4E (Enterprise) Mode
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# 인증: OAuth/SSO (claude login)

export ANTHROPIC_MODEL='${model}'
export CLAUDE_CODE_MAX_OUTPUT_TOKENS=${max_tokens}

# C4E 모드에서는 Bedrock 및 직접 API 관련 변수를 해제
# (ENABLE_PROMPT_CACHING_1H 는 C4E에서 자동 활성화되므로 export 불필요)
unset ANTHROPIC_API_KEY
unset CLAUDE_CODE_USE_BEDROCK
unset AWS_BEARER_TOKEN_BEDROCK
unset ANTHROPIC_DEFAULT_OPUS_MODEL
unset ANTHROPIC_DEFAULT_SONNET_MODEL
unset ANTHROPIC_DEFAULT_HAIKU_MODEL
unset ANTHROPIC_SMALL_FAST_MODEL
EOF

    chmod 600 "$C4E_ENV"
    ok "C4E 프로필 저장: $C4E_ENV"
}

###############################################################################
# 구독형 프로필 설정
###############################################################################
setup_subscription() {
    echo ""
    echo -e "${CYAN}=== 구독형 (Subscription) 프로필 설정 ===${NC}"
    echo ""
    echo -e "${DIM}  Anthropic Pro/Max 구독 사용자용${NC}"
    echo -e "${DIM}  https://console.anthropic.com/ 에서 API Key 발급${NC}"
    echo ""

    # 기존 값이 있으면 보여주기
    local existing_key=""
    if [ -f "$SUB_ENV" ]; then
        existing_key=$(grep "^export ANTHROPIC_API_KEY=" "$SUB_ENV" 2>/dev/null | head -1 | sed "s/export ANTHROPIC_API_KEY=['\"]//;s/['\"]$//" || echo "")
    fi

    if [ -n "$existing_key" ]; then
        local masked="${existing_key:0:10}...${existing_key: -4}"
        echo -e "  현재 API Key: ${DIM}$masked${NC}"
        read -p "  새로 입력하시겠습니까? (y/n) [n]: " CHANGE_KEY
        CHANGE_KEY="${CHANGE_KEY:-n}"
        if [ "$CHANGE_KEY" = "y" ] || [ "$CHANGE_KEY" = "Y" ]; then
            read -p "  ANTHROPIC_API_KEY: " SUB_API_KEY
        else
            SUB_API_KEY="$existing_key"
        fi
    else
        read -p "  ANTHROPIC_API_KEY: " SUB_API_KEY
    fi

    if [ -z "$SUB_API_KEY" ]; then
        fail "ANTHROPIC_API_KEY가 비어있습니다."
    fi

    local model
    model=$(choose_anthropic_model)

    local max_tokens
    max_tokens=$(choose_max_tokens)

    # 프로필 파일 생성
    cat > "$SUB_ENV" << EOF
# Claude Code - Subscription (Pro/Max) Mode
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

export ANTHROPIC_API_KEY='${SUB_API_KEY}'
export ANTHROPIC_MODEL='${model}'
export CLAUDE_CODE_MAX_OUTPUT_TOKENS=${max_tokens}
export ENABLE_PROMPT_CACHING_1H=1

# Subscription 모드에서는 Bedrock 관련 변수를 해제
unset CLAUDE_CODE_USE_BEDROCK
unset AWS_BEARER_TOKEN_BEDROCK
unset ANTHROPIC_DEFAULT_OPUS_MODEL
unset ANTHROPIC_DEFAULT_SONNET_MODEL
unset ANTHROPIC_DEFAULT_HAIKU_MODEL
unset ANTHROPIC_SMALL_FAST_MODEL
EOF

    chmod 600 "$SUB_ENV"
    ok "구독형 프로필 저장: $SUB_ENV"
}

###############################################################################
# Bedrock 프로필 설정
###############################################################################
setup_bedrock() {
    echo ""
    echo -e "${CYAN}=== Bedrock API 프로필 설정 ===${NC}"
    echo ""
    echo -e "${DIM}  Amazon Bedrock 경유 사용자용${NC}"
    echo -e "${DIM}  AWS Console > Bedrock > Model access 에서 모델 활성화 필요${NC}"
    echo ""

    # 기존 값 확인
    local existing_api_key="" existing_bearer=""
    if [ -f "$BRK_ENV" ]; then
        existing_api_key=$(grep "^export ANTHROPIC_API_KEY=" "$BRK_ENV" 2>/dev/null | head -1 | sed "s/export ANTHROPIC_API_KEY=['\"]//;s/['\"]$//" || echo "")
        existing_bearer=$(grep "^export AWS_BEARER_TOKEN_BEDROCK=" "$BRK_ENV" 2>/dev/null | head -1 | sed "s/export AWS_BEARER_TOKEN_BEDROCK=['\"]//;s/['\"]$//" || echo "")
    fi

    # ANTHROPIC_API_KEY
    if [ -n "$existing_api_key" ]; then
        local masked="${existing_api_key:0:10}...${existing_api_key: -4}"
        echo -e "  현재 API Key: ${DIM}$masked${NC}"
        read -p "  새로 입력하시겠습니까? (y/n) [n]: " CHANGE_KEY
        CHANGE_KEY="${CHANGE_KEY:-n}"
        if [ "$CHANGE_KEY" = "y" ] || [ "$CHANGE_KEY" = "Y" ]; then
            read -p "  ANTHROPIC_API_KEY: " BRK_API_KEY
        else
            BRK_API_KEY="$existing_api_key"
        fi
    else
        read -p "  ANTHROPIC_API_KEY: " BRK_API_KEY
    fi

    if [ -z "$BRK_API_KEY" ]; then
        fail "ANTHROPIC_API_KEY가 비어있습니다."
    fi

    # AWS_BEARER_TOKEN_BEDROCK
    if [ -n "$existing_bearer" ]; then
        local masked_b="${existing_bearer:0:10}...${existing_bearer: -4}"
        echo -e "  현재 Bearer Token: ${DIM}$masked_b${NC}"
        read -p "  새로 입력하시겠습니까? (y/n) [n]: " CHANGE_BEARER
        CHANGE_BEARER="${CHANGE_BEARER:-n}"
        if [ "$CHANGE_BEARER" = "y" ] || [ "$CHANGE_BEARER" = "Y" ]; then
            read -p "  AWS_BEARER_TOKEN_BEDROCK: " BRK_BEARER
        else
            BRK_BEARER="$existing_bearer"
        fi
    else
        read -p "  AWS_BEARER_TOKEN_BEDROCK: " BRK_BEARER
    fi

    if [ -z "$BRK_BEARER" ]; then
        fail "AWS_BEARER_TOKEN_BEDROCK가 비어있습니다."
    fi

    # 모델 선택
    echo ""
    echo "  기본 모델 선택:"
    echo "    1) Opus 4.8   (global.anthropic.claude-opus-4-8) (기본값)"
    echo "    2) Opus 4.7   (global.anthropic.claude-opus-4-7)"
    echo "    3) Opus 4.6   (global.anthropic.claude-opus-4-6-v1)"
    echo "    4) Sonnet 4.6 (global.anthropic.claude-sonnet-4-6)"
    read -p "  선택 [1]: " BRK_MODEL_CHOICE
    BRK_MODEL_CHOICE="${BRK_MODEL_CHOICE:-1}"

    case "$BRK_MODEL_CHOICE" in
        2) BRK_MODEL="global.anthropic.claude-opus-4-7" ;;
        3) BRK_MODEL="global.anthropic.claude-opus-4-6-v1" ;;
        4) BRK_MODEL="global.anthropic.claude-sonnet-4-6" ;;
        *) BRK_MODEL="global.anthropic.claude-opus-4-8" ;;
    esac

    local max_tokens
    max_tokens=$(choose_max_tokens)

    # 프로필 파일 생성
    cat > "$BRK_ENV" << EOF
# Claude Code - Bedrock API Mode
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

export ANTHROPIC_API_KEY='${BRK_API_KEY}'
export AWS_BEARER_TOKEN_BEDROCK='${BRK_BEARER}'
export CLAUDE_CODE_USE_BEDROCK=1
export ANTHROPIC_MODEL='${BRK_MODEL}'
export ANTHROPIC_DEFAULT_OPUS_MODEL='global.anthropic.claude-opus-4-8'
export ANTHROPIC_DEFAULT_SONNET_MODEL='global.anthropic.claude-sonnet-4-6'
export ANTHROPIC_DEFAULT_HAIKU_MODEL='global.anthropic.claude-haiku-4-5-20251001-v1:0'
export ANTHROPIC_SMALL_FAST_MODEL='us.anthropic.claude-haiku-4-5-20251001-v1:0'
export CLAUDE_CODE_MAX_OUTPUT_TOKENS=${max_tokens}
export ENABLE_PROMPT_CACHING_1H=1
EOF

    chmod 600 "$BRK_ENV"
    ok "Bedrock 프로필 저장: $BRK_ENV"
}

###############################################################################
# bashrc에 source 라인 등록 (최초 1회)
###############################################################################
ensure_bashrc_hook() {
    if ! grep -qF "$BASHRC_MARKER" "$BASHRC" 2>/dev/null; then
        # 기존 01-setup-bedrock-env.sh 블록이 있으면 주석 처리
        if grep -q "# Claude Code + Amazon Bedrock 설정" "$BASHRC" 2>/dev/null; then
            warn "기존 Bedrock 설정 블록을 비활성화합니다 (주석 처리)."
            if [[ "$(uname)" == "Darwin" ]]; then
                sed -i '' '/# Claude Code + Amazon Bedrock 설정/,/^$/{
                    /^$/!{ /^#/!s/^/# [old] / ; }
                }' "$BASHRC"
            else
                sed -i '/# Claude Code + Amazon Bedrock 설정/,/^$/{
                    /^$/!{ /^#/!s/^/# [old] / }
                }' "$BASHRC"
            fi
        fi

        cat >> "$BASHRC" << 'HOOK'

# Claude Code Mode (managed by 06-switch-mode.sh)
if [ -f "$HOME/.claude-env/active.env" ]; then
    source "$HOME/.claude-env/active.env"
fi
HOOK
        ok "bashrc에 모드 전환 hook 등록 완료"
    fi
}

###############################################################################
# 모드 전환 (활성 프로필 변경)
###############################################################################
switch_to() {
    local target_mode="$1"
    local env_file label

    case "$target_mode" in
        c4e)
            env_file="$C4E_ENV"
            label="C4E (Enterprise)"
            if [ ! -f "$env_file" ]; then
                warn "C4E 프로필이 없습니다. 먼저 설정합니다."
                setup_c4e
            fi
            ;;
        subscription)
            env_file="$SUB_ENV"
            label="구독형 (Subscription)"
            if [ ! -f "$env_file" ]; then
                warn "구독형 프로필이 없습니다. 먼저 설정합니다."
                setup_subscription
            fi
            ;;
        bedrock)
            env_file="$BRK_ENV"
            label="Bedrock API"
            if [ ! -f "$env_file" ]; then
                warn "Bedrock 프로필이 없습니다. 먼저 설정합니다."
                setup_bedrock
            fi
            ;;
        *)
            fail "알 수 없는 모드: $target_mode"
            ;;
    esac

    ln -sf "$env_file" "$ACTIVE_ENV"
    ensure_bashrc_hook

    # 환경변수 즉시 적용
    source "$ACTIVE_ENV"
    ok "환경변수 적용 완료 (source $SHELL_RC)"

    echo ""
    echo -e "${GREEN}=================================================================${NC}"
    echo -e "${GREEN}   모드 전환 완료: ${label}${NC}"
    echo -e "${GREEN}=================================================================${NC}"
    echo ""
    echo -e "  ${DIM}새 터미널에서는 자동으로 적용됩니다.${NC}"
    echo -e "  ${YELLOW}현재 터미널에 바로 적용하려면:${NC}"
    echo ""
    echo -e "    ${BOLD}source $SHELL_RC${NC}"
    echo ""
    if [ "$target_mode" = "c4e" ]; then
        echo -e "  ${CYAN}C4E 로그인 방법:${NC}"
        echo -e "    1. ${BOLD}claude${NC} 명령으로 Claude Code 세션 시작"
        echo -e "    2. 세션 안에서 ${BOLD}/login${NC} 입력"
        echo -e "    3. 표시되는 URL을 브라우저에서 열어 SSO 인증"
        echo ""
    fi
}

###############################################################################
# 대화형 메뉴
###############################################################################
interactive_menu() {
    local current_mode
    current_mode=$(get_current_mode)

    show_status

    echo -e "${BOLD}  작업을 선택하세요 / Select action:${NC}"
    echo ""

    # 모드 전환 메뉴 (현재 활성 모드에 (현재) 표시)
    local c4e_tag="" sub_tag="" brk_tag=""
    case "$current_mode" in
        c4e)          c4e_tag=" ${DIM}(현재 활성)${NC}" ;;
        subscription) sub_tag=" ${DIM}(현재 활성)${NC}" ;;
        bedrock)      brk_tag=" ${DIM}(현재 활성)${NC}" ;;
    esac

    echo -e "    ${BOLD}[모드 전환]${NC}"
    echo -e "    1) ${GREEN}C4E (Enterprise, OAuth)${NC}${c4e_tag}"
    echo -e "    2) ${CYAN}구독형 (Subscription, API Key)${NC}${sub_tag}"
    echo -e "    3) ${YELLOW}Bedrock API${NC}${brk_tag}"
    echo ""
    echo -e "    ${BOLD}[프로필 재설정]${NC}"
    echo -e "    4) C4E 프로필 재설정"
    echo -e "    5) 구독형 프로필 재설정"
    echo -e "    6) Bedrock 프로필 재설정"
    echo -e "    7) 전체 프로필 재설정"
    echo ""
    echo -e "    q) 종료"
    echo ""
    read -p "  선택 / Enter number: " CHOICE

    case "$CHOICE" in
        1)
            if [ "$current_mode" = "c4e" ]; then
                info "이미 C4E 모드입니다."
            else
                switch_to c4e
            fi
            ;;
        2)
            if [ "$current_mode" = "subscription" ]; then
                info "이미 구독형 모드입니다."
            else
                switch_to subscription
            fi
            ;;
        3)
            if [ "$current_mode" = "bedrock" ]; then
                info "이미 Bedrock 모드입니다."
            else
                switch_to bedrock
            fi
            ;;
        4)
            setup_c4e
            [ "$current_mode" = "c4e" ] && switch_to c4e || ok "C4E 프로필이 업데이트되었습니다."
            ;;
        5)
            setup_subscription
            [ "$current_mode" = "subscription" ] && switch_to subscription || ok "구독형 프로필이 업데이트되었습니다."
            ;;
        6)
            setup_bedrock
            [ "$current_mode" = "bedrock" ] && switch_to bedrock || ok "Bedrock 프로필이 업데이트되었습니다."
            ;;
        7)
            setup_c4e
            echo ""
            setup_subscription
            echo ""
            setup_bedrock
            echo ""
            echo -e "${BOLD}  활성화할 모드를 선택하세요:${NC}"
            echo "    1) C4E (Enterprise, OAuth)"
            echo "    2) 구독형 (Subscription)"
            echo "    3) Bedrock API"
            read -p "  선택 [1]: " ACTIVATE
            ACTIVATE="${ACTIVATE:-1}"
            case "$ACTIVATE" in
                2) switch_to subscription ;;
                3) switch_to bedrock ;;
                *) switch_to c4e ;;
            esac
            ;;
        q|Q)
            echo "  종료합니다."
            exit 0
            ;;
        *)
            warn "잘못된 선택입니다."
            exit 1
            ;;
    esac
}

###############################################################################
# 메인
###############################################################################
mkdir -p "$ENV_DIR"

case "${1:-}" in
    status)
        show_status
        ;;
    c4e)
        switch_to c4e
        ;;
    subscription|sub)
        switch_to subscription
        ;;
    bedrock|brk)
        switch_to bedrock
        ;;
    setup)
        setup_c4e
        echo ""
        setup_subscription
        echo ""
        setup_bedrock
        echo ""
        echo -e "${BOLD}  활성화할 모드를 선택하세요:${NC}"
        echo "    1) C4E (Enterprise, OAuth)"
        echo "    2) 구독형 (Subscription)"
        echo "    3) Bedrock API"
        read -p "  선택 [1]: " ACTIVATE
        ACTIVATE="${ACTIVATE:-1}"
        case "$ACTIVATE" in
            2) switch_to subscription ;;
            3) switch_to bedrock ;;
            *) switch_to c4e ;;
        esac
        ;;
    -h|--help)
        echo ""
        echo "Claude Code 모드 전환 스크립트"
        echo ""
        echo "사용법:"
        echo "  bash $0                대화형 전환"
        echo "  bash $0 status         현재 모드 확인"
        echo "  bash $0 c4e            C4E (Enterprise)로 즉시 전환"
        echo "  bash $0 subscription   구독형으로 즉시 전환"
        echo "  bash $0 bedrock        Bedrock으로 즉시 전환"
        echo "  bash $0 setup          전체 프로필 재설정"
        echo ""
        echo "프로필 경로:"
        echo "  $C4E_ENV"
        echo "  $SUB_ENV"
        echo "  $BRK_ENV"
        echo "  $ACTIVE_ENV (symlink → 활성 프로필)"
        echo ""
        echo "모드 비교:"
        echo "  C4E          OAuth/SSO 인증, API Key 불필요, claude login 사용"
        echo "  Subscription Anthropic API Key 사용, 직접 연결"
        echo "  Bedrock      API Key + Bearer Token, Amazon Bedrock 경유"
        echo ""
        ;;
    "")
        interactive_menu
        ;;
    *)
        fail "알 수 없는 명령: $1 (--help 참조)"
        ;;
esac
