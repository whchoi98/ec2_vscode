#!/bin/bash
###############################################################################
# Claude Code - claude-hud (statusLine HUD) 설치/설정 스크립트
#
# jarrodwatts/claude-hud 마켓플레이스를 등록하고 플러그인을 설치한 뒤,
# ~/.claude/settings.json 에 statusLine 명령을 기록합니다.
# (대화형 /claude-hud:setup 이 수행하는 작업을 비대화형으로 재현)
#
# - 런타임(bun/node)을 자동 감지하여 명령을 생성합니다.
# - 생성 명령은 실행 시점에 최신 설치 버전을 동적 탐색하므로
#   플러그인 업데이트 후 재실행이 불필요합니다.
# - 확장 표시 기능(Tools/Agents/Todos/Session)을 config.json 에 활성화합니다.
###############################################################################

set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
HUD_CONFIG_DIR="$CLAUDE_DIR/plugins/claude-hud"
HUD_CONFIG="$HUD_CONFIG_DIR/config.json"

###############################################################################
# 1. 사전 요구사항 확인
###############################################################################
info "=== 사전 요구사항 확인 ==="

if command -v claude >/dev/null 2>&1; then
    ok "claude CLI: $(claude --version 2>&1 | head -1)"
else
    fail "claude CLI가 설치되어 있지 않습니다. 설치: https://docs.anthropic.com/en/docs/claude-code"
fi

# 런타임 감지 (bun 우선, node 폴백)
RUNTIME_PATH=$(command -v bun 2>/dev/null || command -v node 2>/dev/null || true)
if [ -z "$RUNTIME_PATH" ]; then
    fail "node 또는 bun 런타임을 찾을 수 없습니다. Node.js LTS(https://nodejs.org) 설치 후 다시 실행하세요."
fi

# node 는 dist/index.js, bun 은 src/index.ts (+ --env-file /dev/null)
case "$RUNTIME_PATH" in
    *bun*) RUNTIME_KIND="bun";  SOURCE_ARGS='--env-file /dev/null "${plugin_dir}src/index.ts"' ;;
    *)     RUNTIME_KIND="node"; SOURCE_ARGS='"${plugin_dir}dist/index.js"' ;;
esac
ok "런타임: $RUNTIME_PATH ($RUNTIME_KIND)"

echo ""

###############################################################################
# 2. 마켓플레이스 등록 + 플러그인 설치
###############################################################################
info "=== claude-hud 마켓플레이스 등록 ==="

if [ -d "$CLAUDE_DIR/plugins/marketplaces/claude-hud" ]; then
    ok "claude-hud 마켓플레이스 이미 존재"
else
    info "jarrodwatts/claude-hud 추가 중..."
    claude plugin marketplace add jarrodwatts/claude-hud 2>&1 && ok "마켓플레이스 추가 완료" || warn "추가 실패"
fi

echo ""
info "=== claude-hud 플러그인 설치 ==="
if claude plugin install "claude-hud@claude-hud" 2>&1; then
    ok "claude-hud 설치 완료"
else
    warn "claude-hud (이미 설치되어 있거나 설치 실패)"
fi

# 설치된 플러그인 경로 확인
PLUGIN_DIR=$(ls -d "$CLAUDE_DIR"/plugins/cache/*/claude-hud/*/ 2>/dev/null \
    | awk -F/ '{ print $(NF-1) "\t" $(0) }' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+[[:space:]]' \
    | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1 | cut -f2-)
if [ -z "$PLUGIN_DIR" ]; then
    fail "claude-hud 플러그인 캐시를 찾을 수 없습니다. 설치가 완료되지 않았습니다."
fi
ok "플러그인 경로: $PLUGIN_DIR"

echo ""

###############################################################################
# 3. statusLine 명령 생성 (리터럴 템플릿 -> node 로 치환/병합)
###############################################################################
info "=== statusLine 설정 ==="

TMP_TEMPLATE=$(mktemp)
# quoted heredoc: 내부는 전부 리터럴 (셸 확장 없음)
cat > "$TMP_TEMPLATE" <<'TPLEOF'
bash -c 'cols=${COLUMNS:-}; case "$cols" in ""|*[!0-9]*) cols=$(stty size </dev/tty 2>/dev/null | awk '"'"'{print $2}'"'"');; esac; case "$cols" in ""|*[!0-9]*) cols=120;; esac; export COLUMNS=$(( cols > 4 ? cols - 4 : 1 )); plugin_dir=$(ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/*/claude-hud/*/ 2>/dev/null | awk -F/ '"'"'{ print $(NF-1) "\t" $(0) }'"'"' | grep -E '"'"'^[0-9]+\.[0-9]+\.[0-9]+[[:space:]]'"'"' | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1 | cut -f2-); exec "@@RUNTIME@@" @@SOURCE_ARGS@@'
TPLEOF

# settings.json 백업
if [ -f "$SETTINGS" ]; then
    BACKUP="$SETTINGS.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$SETTINGS" "$BACKUP" && ok "settings.json 백업: $BACKUP"
fi

# node 로 안전하게 치환 + JSON 병합 (기존 설정 보존)
RUNTIME_PATH="$RUNTIME_PATH" SOURCE_ARGS="$SOURCE_ARGS" \
"$RUNTIME_PATH" -e '
const fs = require("fs");
const [settingsPath, tplPath] = process.argv.slice(1);
let cmd = fs.readFileSync(tplPath, "utf8").replace(/\n+$/, "");
cmd = cmd.split("@@RUNTIME@@").join(process.env.RUNTIME_PATH)
         .split("@@SOURCE_ARGS@@").join(process.env.SOURCE_ARGS);
let json = {};
if (fs.existsSync(settingsPath)) {
  const t = fs.readFileSync(settingsPath, "utf8");
  if (t.trim() !== "") {
    try { json = JSON.parse(t); }
    catch (e) { console.error("settings.json JSON 파싱 실패, 중단: " + e.message); process.exit(1); }
  }
}
json.statusLine = { type: "command", command: cmd };
fs.writeFileSync(settingsPath, JSON.stringify(json, null, 2) + "\n", "utf8");
console.log("statusLine 기록 완료");
' "$SETTINGS" "$TMP_TEMPLATE" && ok "statusLine 병합 완료" || fail "statusLine 설정 실패"

rm -f "$TMP_TEMPLATE"

echo ""

###############################################################################
# 4. 확장 표시 기능 활성화 (config.json)
###############################################################################
info "=== HUD 확장 기능 설정 (config.json) ==="

mkdir -p "$HUD_CONFIG_DIR"
"$RUNTIME_PATH" -e '
const fs = require("fs");
const p = process.argv[1];
let json = {};
if (fs.existsSync(p)) {
  const t = fs.readFileSync(p, "utf8");
  if (t.trim() !== "") { try { json = JSON.parse(t); } catch(e){ console.error("config.json 파싱 실패: "+e.message); process.exit(1);} }
}
json.display = Object.assign({}, json.display, {
  showTools: true,
  showAgents: true,
  showTodos: true,
  showDuration: true,
  showConfigCounts: true,
  showSessionName: true
});
fs.writeFileSync(p, JSON.stringify(json, null, 2) + "\n", "utf8");
console.log("확장 기능 활성화: Tools, Agents, Todos, Session info/name");
' "$HUD_CONFIG" && ok "config.json 설정 완료" || warn "config.json 설정 실패"

echo ""

###############################################################################
# 5. 명령 검증 + 결과 요약
###############################################################################
info "=== 설정 검증 ==="
GEN_CMD=$("$RUNTIME_PATH" -e 'const j=require(process.argv[1]); process.stdout.write(j.statusLine.command);' "$SETTINGS")
if echo '{"workspace":{"current_dir":"'"$PWD"'"},"model":{"display_name":"test"}}' | eval "$GEN_CMD" >/dev/null 2>&1; then
    ok "statusLine 명령 실행 테스트 통과"
else
    warn "명령 테스트에서 경고가 발생했습니다 (TTY 미존재 환경에서는 정상일 수 있음)."
fi

echo ""
ok "claude-hud 설정이 완료되었습니다!"
echo ""
echo "  [플러그인]  claude-hud (statusLine HUD)"
echo "  [런타임]    $RUNTIME_PATH ($RUNTIME_KIND)"
echo "  [설정 파일] $SETTINGS (statusLine)"
echo "              $HUD_CONFIG (확장 기능)"
echo ""
echo "  ▶ Claude Code를 재시작하면 입력창 아래에 HUD가 표시됩니다."
echo "    (설정을 실행한 현재 세션에서는 표시되지 않습니다.)"
