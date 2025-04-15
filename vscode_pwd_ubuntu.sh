#!/bin/bash

# 사용자로부터 비밀번호 입력받기
read -s -p "Enter the password to set: " PASSWORD
echo
read -s -p "Confirm the password: " PASSWORD_CONFIRM
echo

# 비밀번호 일치 확인
if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
    echo "Passwords do not match. Exiting."
    exit 1
fi

# 비밀번호 해시 생성 (SHA-256은 실제 인증에 적합하지 않음 – 예시용)
PASSWORD_HASH=$(echo -n "$PASSWORD" | sha256sum | awk '{print $1}')

# code-server 설정 파일 경로
CONFIG_DIR="/home/ubuntu/.config/code-server"
CONFIG_FILE="$CONFIG_DIR/config.yaml"

# 디렉토리 생성 및 설정 파일 작성
mkdir -p "$CONFIG_DIR"
cat <<EOF > "$CONFIG_FILE"
bind-addr: 0.0.0.0:8888
auth: password
hashed-password: $PASSWORD_HASH
cert: false
EOF

# 권한 설정
chown -R ubuntu:ubuntu "$CONFIG_DIR"

# systemd 서비스 재시작
sudo systemctl daemon-reload
sudo systemctl restart code-server

echo "✅ VS Code Server password authentication is now enabled."
