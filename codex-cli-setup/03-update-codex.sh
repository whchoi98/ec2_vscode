#!/usr/bin/env bash
# Update the detected CLI, or install under the current user's npm prefix.
set -euo pipefail

DRY_RUN=false
case "${1:-}" in
    --dry-run) DRY_RUN=true; shift ;;
    --help|-h)
        echo "사용법: bash 03-update-codex.sh [--dry-run]"
        echo "신규 설치 경로: CODEX_INSTALL_PREFIX (기본값: ~/.npm-global)"
        echo "PATH 기록 파일: CODEX_SHELL_RC (기본값: ~/.bashrc)"
        exit 0
        ;;
esac
if [ "$#" -ne 0 ]; then
    echo "지원하지 않는 인자입니다. --help를 확인하세요." >&2
    exit 1
fi

echo "=== Codex CLI 설치/업데이트 ==="
if command -v codex >/dev/null 2>&1; then
    echo "현재 실행 경로: $(command -v codex)"
    codex --version
    if codex update --help >/dev/null 2>&1; then
        if "$DRY_RUN"; then
            echo "미리보기: 현재 설치본에서 codex update를 실행합니다."
            exit 0
        fi
        codex update
        codex --version
        exit 0
    fi
fi

for dependency in node npm; do
    if ! command -v "$dependency" >/dev/null 2>&1; then
        echo "$dependency 명령어가 필요합니다. Node.js와 npm을 설치하세요." >&2
        exit 1
    fi
done

INSTALL_PREFIX="${CODEX_INSTALL_PREFIX:-$HOME/.npm-global}"
SHELL_RC="${CODEX_SHELL_RC:-$HOME/.bashrc}"
if [[ "$INSTALL_PREFIX" != /* ]]; then
    echo "CODEX_INSTALL_PREFIX는 절대 경로여야 합니다." >&2
    exit 1
fi
if "$DRY_RUN"; then
    printf '미리보기: npm install --global --prefix %q @openai/codex@latest\n' "$INSTALL_PREFIX"
    printf 'PATH 기록 파일: %s\n' "$SHELL_RC"
    exit 0
fi

npm install --global --prefix "$INSTALL_PREFIX" @openai/codex@latest
"$INSTALL_PREFIX/bin/codex" --version

# Quote the prefix as shell data, including paths containing spaces.
printf -v PATH_LINE 'export PATH=%q:"$PATH"' "$INSTALL_PREFIX/bin"
if ! grep -Fqx -- "$PATH_LINE" "$SHELL_RC" 2>/dev/null; then
    printf '\n# Codex CLI user installation\n%s\n' "$PATH_LINE" >> "$SHELL_RC"
fi

echo "설치 경로: $INSTALL_PREFIX/bin/codex"
printf '현재 셸에 PATH 적용: source %q\n' "$SHELL_RC"
echo "인증 및 모델 설정: bash codex-cli-setup/01-setup-env.sh"
