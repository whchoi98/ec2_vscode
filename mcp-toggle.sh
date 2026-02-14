#!/bin/bash

MCP_CONFIG=""
BACKUP_CONFIG=""

# MCP 설정 파일 확인 및 경로 선택
check_mcp_config() {
    local kiro_config="$HOME/.kiro/settings/mcp.json"
    local claude_config="$HOME/.claude.json"
    
    echo -e "${BOLD}${BLUE}=== MCP 설정 파일 선택 ===${NC}"
    echo ""
    
    # 사용 가능한 설정 파일 확인
    local options=()
    local found_files=()
    
    if [[ -f "$kiro_config" ]]; then
        options+=("1")
        found_files+=("$kiro_config")
        echo -e "${GREEN}1) Kiro CLI: $kiro_config${NC}"
    else
        echo -e "${RED}1) Kiro CLI: $kiro_config (파일 없음)${NC}"
    fi
    
    if [[ -f "$claude_config" ]]; then
        options+=("2")
        found_files+=("$claude_config")
        echo -e "${GREEN}2) Claude Desktop: $claude_config${NC}"
    else
        echo -e "${RED}2) Claude Desktop: $claude_config (파일 없음)${NC}"
    fi
    
    echo -e "${YELLOW}3) 직접 입력${NC}"
    echo -e "${YELLOW}q) 종료${NC}"
    echo ""
    
    while true; do
        read -p "선택하세요 (1/2/3/q): " choice
        
        case "$choice" in
            "1")
                if [[ -f "$kiro_config" ]]; then
                    MCP_CONFIG="$kiro_config"
                    BACKUP_CONFIG="${kiro_config}.backup"
                    echo -e "${GREEN}✅ Kiro CLI 설정을 선택했습니다${NC}"
                    break
                else
                    echo -e "${RED}Kiro CLI 설정 파일이 존재하지 않습니다${NC}"
                fi
                ;;
            "2")
                if [[ -f "$claude_config" ]]; then
                    MCP_CONFIG="$claude_config"
                    BACKUP_CONFIG="${claude_config}.backup"
                    echo -e "${GREEN}✅ Claude Desktop 설정을 선택했습니다${NC}"
                    break
                else
                    echo -e "${RED}Claude Desktop 설정 파일이 존재하지 않습니다${NC}"
                fi
                ;;
            "3")
                echo ""
                echo -e "${YELLOW}MCP 설정 파일 경로를 입력하세요:${NC}"
                read -p "> " user_path
                
                # 경로 확장 (~ 처리)
                user_path="${user_path/#\~/$HOME}"
                
                if [[ -f "$user_path" ]]; then
                    MCP_CONFIG="$user_path"
                    BACKUP_CONFIG="${user_path}.backup"
                    echo -e "${GREEN}✅ 사용자 지정 설정을 선택했습니다: $MCP_CONFIG${NC}"
                    break
                else
                    echo -e "${RED}파일을 찾을 수 없습니다: $user_path${NC}"
                fi
                ;;
            "q"|"Q")
                echo -e "${YELLOW}종료합니다.${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}잘못된 선택입니다. 1, 2, 3, 또는 q를 입력하세요.${NC}"
                ;;
        esac
    done
    
    echo ""
}

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# 현재 선택된 항목
current_selection=0
declare -a server_list
declare -A server_status
declare -A server_descriptions

load_servers() {
    server_list=()
    server_status=()
    server_descriptions=()
    
    # Claude Desktop 설정 파일인지 확인
    local is_claude_config=false
    if [[ "$MCP_CONFIG" == *".claude.json" ]]; then
        is_claude_config=true
    fi
    
    if [[ "$is_claude_config" == true ]]; then
        # Claude Desktop 설정 구조: .mcpServers
        while IFS= read -r server; do
            server_list+=("$server")
            local disabled=$(jq -r ".mcpServers[\"$server\"].disabled // false" "$MCP_CONFIG")
            server_status["$server"]="$disabled"
            
            local desc=$(jq -r ".mcpServers[\"$server\"]._description // \"설명 없음\"" "$MCP_CONFIG")
            server_descriptions["$server"]="$desc"
        done < <(jq -r '.mcpServers | keys[]' "$MCP_CONFIG" 2>/dev/null || echo "")
    else
        # Kiro CLI 설정 구조: .mcpServers
        while IFS= read -r server; do
            server_list+=("$server")
            local disabled=$(jq -r ".mcpServers[\"$server\"].disabled // false" "$MCP_CONFIG")
            server_status["$server"]="$disabled"
            
            local desc=$(jq -r ".mcpServers[\"$server\"]._description // \"설명 없음\"" "$MCP_CONFIG")
            server_descriptions["$server"]="$desc"
        done < <(jq -r '.mcpServers | keys[]' "$MCP_CONFIG" 2>/dev/null || echo "")
    fi
    
    if [[ ${#server_list[@]} -eq 0 ]]; then
        echo -e "${RED}오류: MCP 서버를 찾을 수 없습니다. 설정 파일 형식을 확인하세요.${NC}"
        exit 1
    fi
}

draw_menu() {
    clear
    echo -e "${BOLD}${BLUE}=== MCP 서버 관리 도구 ===${NC}"
    echo -e "${CYAN}설정 파일: $MCP_CONFIG${NC}"
    echo -e "${CYAN}t: 토글 | s: 저장 후 종료 | q: 종료${NC}"
    echo ""
    
    for i in "${!server_list[@]}"; do
        local server="${server_list[$i]}"
        local disabled="${server_status[$server]}"
        local desc="${server_descriptions[$server]}"
        
        # 상태 표시
        local status_color="${GREEN}"
        local status_text="[ON ]"
        if [[ "$disabled" == "true" ]]; then
            status_color="${RED}"
            status_text="[OFF]"
        fi
        
        # 선택된 항목 표시
        local prefix="  "
        if [[ $i -eq $current_selection ]]; then
            prefix="${YELLOW}> ${NC}"
        fi
        
        printf "%b%b%s${NC} %-40s - %s\n" \
            "$prefix" \
            "$status_color" \
            "$status_text" \
            "$server" \
            "$desc"
    done
    
    echo ""
    echo -e "${CYAN}t: 토글 | s: 저장 후 종료 | q: 종료${NC}"
}

toggle_server() {
    local server="${server_list[$current_selection]}"
    local current_status="${server_status[$server]}"
    
    if [[ "$current_status" == "true" ]]; then
        server_status["$server"]="false"
    else
        server_status["$server"]="true"
    fi
}

apply_changes() {
    # 백업 생성
    cp "$MCP_CONFIG" "$BACKUP_CONFIG"
    
    # 변경사항 적용
    local temp_file="/tmp/mcp_temp.json"
    cp "$MCP_CONFIG" "$temp_file"
    
    for server in "${server_list[@]}"; do
        local new_status="${server_status[$server]}"
        jq ".mcpServers[\"$server\"].disabled = $new_status" "$temp_file" > "$temp_file.tmp" && \
        mv "$temp_file.tmp" "$temp_file"
    done
    
    mv "$temp_file" "$MCP_CONFIG"
    
    echo -e "${GREEN}✅ 설정이 적용되었습니다!${NC}"
    echo -e "${YELLOW}Kiro CLI를 재시작하여 변경사항을 적용하세요.${NC}"
    echo ""
    read -p "아무 키나 누르세요..." -n1
}

main() {
    check_mcp_config
    
    load_servers
    
    while true; do
        draw_menu
        
        # 키 입력 받기
        read -rsn1 key
        
        # 키 코드 확인을 위한 디버깅 (필요시 주석 해제)
        # printf "Key pressed: '%s' (ASCII: %d)\n" "$key" "'$key" >&2
        
        case "$key" in
            $'\x1b')  # ESC 시퀀스 시작
                read -rsn2 key
                case "$key" in
                    '[A')  # 위 화살표
                        ((current_selection--))
                        if [[ $current_selection -lt 0 ]]; then
                            current_selection=$((${#server_list[@]} - 1))
                        fi
                        ;;
                    '[B')  # 아래 화살표
                        ((current_selection++))
                        if [[ $current_selection -ge ${#server_list[@]} ]]; then
                            current_selection=0
                        fi
                        ;;
                esac
                ;;
            $' '|' ')  # 스페이스바 (비활성화)
                # 스페이스바는 비활성화됨
                ;;
            $'\n'|$'\r')  # Enter - 무시
                continue
                ;;
            's'|'S')  # s 키 - 저장 후 종료
                apply_changes
                break
                ;;
            '')  # 빈 입력 무시
                continue
                ;;
            'q'|'Q')  # 변경사항 저장하지 않고 종료
                echo -e "\n${YELLOW}변경사항을 저장하지 않고 종료합니다.${NC}"
                exit 0
                ;;
            'j')  # vim 스타일 아래
                ((current_selection++))
                if [[ $current_selection -ge ${#server_list[@]} ]]; then
                    current_selection=0
                fi
                ;;
            'k')  # vim 스타일 위
                ((current_selection--))
                if [[ $current_selection -lt 0 ]]; then
                    current_selection=$((${#server_list[@]} - 1))
                fi
                ;;
            't'|'T')  # t 키로 토글
                toggle_server
                ;;
        esac
    done
}

# 도움말 표시
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "MCP 서버 인터랙티브 관리 도구"
    echo ""
    echo "사용법: $0"
    echo ""
    echo "키 조작:"
    echo "  ↑/↓ 또는 k/j  - 항목 이동"
    echo "  t             - 서버 활성화/비활성화 토글"
    echo "  s             - 변경사항 저장 후 종료"
    echo "  q             - 변경사항 저장하지 않고 종료"
    exit 0
fi

main
