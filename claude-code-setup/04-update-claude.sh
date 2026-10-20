#!/bin/bash

# ─────────────────────────────────────────────────
# Claude Code 업데이트 / 롤백 스크립트
# 사용법:
#   ./04-update-claude.sh              # 최신 버전으로 업데이트
#   ./04-update-claude.sh --rollback 2.1.100  # 특정 버전으로 롤백
#   ./04-update-claude.sh --list       # 설치 가능한 버전 목록 표시
# ─────────────────────────────────────────────────

# 릴리스 노트 가져오기 함수
show_release_notes() {
    local VERSION="$1"
    echo ""
    echo "📋 v${VERSION} 릴리스 노트:"
    echo "────────────────────────────────────────"

    local RELEASE_BODY=""
    if command -v curl &>/dev/null; then
        local RELEASE_JSON
        RELEASE_JSON=$(curl -sf --max-time 10 \
            "https://api.github.com/repos/anthropics/claude-code/releases/tags/v${VERSION}" \
            2>/dev/null || true)
        if [ -n "$RELEASE_JSON" ]; then
            if command -v python3 &>/dev/null; then
                RELEASE_BODY=$(echo "$RELEASE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('body',''))" 2>/dev/null || true)
            else
                RELEASE_BODY=$(echo "$RELEASE_JSON" | sed -n 's/.*"body"[[:space:]]*:[[:space:]]*"//p' | sed 's/"[[:space:]]*$//' | sed 's/\\r\\n/\n/g; s/\\n/\n/g' || true)
            fi
        fi
    fi

    if [ -n "$RELEASE_BODY" ]; then
        echo "$RELEASE_BODY" \
            | sed 's/\\r\\n/\n/g; s/\\n/\n/g; s/\\t/\t/g; s/\\"/"/g' \
            | sed -n '/^##\|^- \|^\* \|^[0-9]\./p' \
            | head -30
    else
        echo "  릴리스 노트를 가져올 수 없습니다."
        echo "  → https://github.com/anthropics/claude-code/releases/tag/v${VERSION}"
    fi
    echo "────────────────────────────────────────"
}

# npm 글로벌 명령 래퍼: 글로벌 prefix에 쓰기 권한이 없을 때만 sudo 사용
# (sudo npm은 root의 npm 설정을 쓰므로, ~/.npmrc prefix가 있으면 다른 위치에 설치됨)
npm_global() {
    if [ -w "$(npm prefix -g)" ]; then
        npm "$@"
    else
        sudo npm "$@"
    fi
}

# 현재 버전 확인
OLD_VERSION=$(claude --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")

# 설치 방식 감지: 네이티브(~/.local/share/claude) 또는 npm
CLAUDE_BIN="$(command -v claude 2>/dev/null || true)"
if [ -n "$CLAUDE_BIN" ] && [[ "$(readlink -f "$CLAUDE_BIN")" == "$HOME/.local/share/claude/"* ]]; then
    INSTALL_METHOD="native"
else
    INSTALL_METHOD="npm"
fi

# ─────────────────────────────────────────────────
# --list: 설치 가능한 버전 목록
# ─────────────────────────────────────────────────
if [ "$1" = "--list" ]; then
    echo "=== Claude Code 버전 목록 ==="
    echo ""
    echo "현재 설치된 버전: $OLD_VERSION"
    echo ""
    echo "📌 채널별 최신 버전:"
    npm view @anthropic-ai/claude-code dist-tags --json 2>/dev/null \
        | sed 's/[{}]//g; s/,/\n/g; s/"//g' \
        | sed 's/^/  /' | grep -v '^[[:space:]]*$'
    echo ""
    echo "📦 최근 릴리스 버전 (최신순 20개):"
    npm view @anthropic-ai/claude-code versions --json 2>/dev/null \
        | python3 -c "import sys,json; [print(f'  {v}') for v in json.load(sys.stdin)[-20:]]" 2>/dev/null \
        || npm view @anthropic-ai/claude-code versions --json 2>/dev/null | tail -22
    echo ""
    echo "사용법: $0 --rollback <버전>"
    exit 0
fi

# ─────────────────────────────────────────────────
# --rollback <version>: 특정 버전으로 롤백
# ─────────────────────────────────────────────────
if [ "$1" = "--rollback" ]; then
    TARGET_VERSION="$2"

    if [ -z "$TARGET_VERSION" ]; then
        echo "❌ 롤백할 버전을 지정해주세요."
        echo "   사용법: $0 --rollback <버전>"
        echo "   예시:   $0 --rollback 2.1.100"
        echo ""
        echo "   버전 목록 확인: $0 --list"
        exit 1
    fi

    echo "=== Claude Code 롤백 ==="
    echo ""
    echo "현재 버전:  $OLD_VERSION"
    echo "대상 버전:  $TARGET_VERSION"
    echo ""

    # 대상 버전 존재 여부 확인
    VERSION_EXISTS=$(npm view "@anthropic-ai/claude-code@${TARGET_VERSION}" version 2>/dev/null || true)
    if [ -z "$VERSION_EXISTS" ]; then
        echo "❌ 버전 ${TARGET_VERSION}을 찾을 수 없습니다."
        echo "   $0 --list 로 설치 가능한 버전을 확인하세요."
        exit 1
    fi

    if [ "$OLD_VERSION" = "$TARGET_VERSION" ]; then
        echo "ℹ️  이미 v${TARGET_VERSION}이 설치되어 있습니다."
        exit 0
    fi

    # macOS: brew cask 설치 여부 확인
    if [[ "$(uname)" == "Darwin" ]] && brew list --cask claude-code &>/dev/null; then
        echo "⚠️  brew cask로 설치되어 있어 먼저 제거합니다..."
        brew uninstall --cask claude-code
    fi

    echo "v${TARGET_VERSION} 설치 중... (설치 방식: $INSTALL_METHOD)"
    if [ "$INSTALL_METHOD" = "native" ]; then
        claude install --force "$TARGET_VERSION"
    else
        npm_global install -g "@anthropic-ai/claude-code@${TARGET_VERSION}"
    fi

    NEW_VERSION=$(claude --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    echo ""
    echo "✅ 롤백 완료! $OLD_VERSION → $NEW_VERSION"

    show_release_notes "$NEW_VERSION"

    echo ""
    if [ "$INSTALL_METHOD" = "native" ]; then
        echo "⚠️  네이티브 설치는 자동 업데이트되므로 곧 최신 버전으로 돌아갑니다."
        echo "   버전을 고정하려면 DISABLE_AUTOUPDATER=1 을 설정하세요."
    fi
    echo "💡 최신 버전으로 복원하려면: $0"
    echo "=== 롤백 완료 ==="
    exit 0
fi

# ─────────────────────────────────────────────────
# 기본 동작: 최신 버전으로 업데이트
# ─────────────────────────────────────────────────
echo "=== Claude Code 업데이트 시작 ==="
echo ""
echo "현재 버전: $OLD_VERSION"
echo ""

# 업데이트 실행 (npm latest 채널 사용 — brew cask는 stable 채널이라 버전이 느림)
echo "업데이트 중... (설치 방식: $INSTALL_METHOD)"
if [ "$INSTALL_METHOD" = "native" ]; then
    # 네이티브 설치: 사용자 홈에 설치되어 sudo 불필요
    claude update
elif [[ "$(uname)" == "Darwin" ]]; then
    # macOS: brew cask가 설치되어 있으면 제거 안내 후 npm으로 통일
    if brew list --cask claude-code &>/dev/null; then
        echo "⚠️  brew cask (stable 채널)로 설치되어 있습니다."
        echo "   npm (latest 채널)이 더 빠르게 최신 버전을 제공합니다."
        echo ""
        read -p "brew cask를 제거하고 npm으로 전환하시겠습니까? (y/n, 기본값: y): " SWITCH
        if [ "$SWITCH" != "n" ] && [ "$SWITCH" != "N" ]; then
            echo "brew cask 제거 중..."
            brew uninstall --cask claude-code
            echo "npm으로 설치 중..."
            npm_global install -g @anthropic-ai/claude-code
        else
            echo "brew cask로 업데이트합니다 (stable 채널)..."
            brew upgrade claude-code
        fi
    else
        npm_global update -g @anthropic-ai/claude-code
    fi
else
    npm_global update -g @anthropic-ai/claude-code
fi

# 업데이트 후 버전 확인
NEW_VERSION=$(claude --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
echo ""
echo "업데이트 완료! 새 버전: $NEW_VERSION"

# 버전 변경 시 릴리스 노트(새 기능 요약) 출력
if [ "$OLD_VERSION" = "$NEW_VERSION" ]; then
    echo ""
    echo "ℹ️  이미 최신 버전입니다."
else
    show_release_notes "$NEW_VERSION"
fi

if [ "$INSTALL_METHOD" = "npm" ]; then
    echo ""
    echo "💡 네이티브 설치로 전환하면 sudo 없이 자동 업데이트됩니다: claude install"
fi

echo ""
echo "=== 업데이트 완료 ==="
