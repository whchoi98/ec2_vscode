#!/bin/bash

echo "=== Claude Code 업데이트 시작 ==="
echo ""

# 현재 버전 확인
echo "현재 버전:"
claude --version
echo ""

# 업데이트 실행
echo "업데이트 중..."
sudo npm update -g @anthropic-ai/claude-code

# 업데이트 후 버전 확인
echo ""
echo "업데이트 완료! 새 버전:"
claude --version
echo ""
echo "=== 업데이트 완료 ==="
