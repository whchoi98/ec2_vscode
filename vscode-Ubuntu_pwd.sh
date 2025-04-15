#!/bin/bash

# 사용자로부터 비밀번호 입력받기
read -s -p "Enter the password to set: " PASSWORD
echo
read -s -p "Confirm the password: " PASSWORD_CONFIRM
echo

# 비밀번호 일치 여부 확인
if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
    echo "❌ Passwords do not match. Exiting."
    exit 1
fi

# bcrypt 해시 생성 (Python 사용)
if ! command -v python3 &> /dev/null; then
    echo "❌ Python3 is not installed. Please install it and retry."
    exit 1
fi

PASSWORD_HASH=$(python3 -c "import bcrypt; print(bcrypt.hashpw(b'$PASSWORD', bcrypt.gensalt()).decode())")

# VS Code Server 설정 경로
CONFIG_DIR="/home/ubuntu/.config/code-server"
CONFIG_FILE="$CONFIG_DIR/config.yaml"

# 설정 파일 생성
echo "🔧 Updating VS Code Server config..."
sudo mkdir -p $CONFIG_DIR
sudo bash -c "cat > $CONFIG_FILE" <<EOF
bind-addr: 0.0.0.0:8888
auth: password
hashed-password: $PASSWORD_HASH
cert: false
EOF

# 권한 설정
sudo chown -R ubuntu:ubuntu $CONFIG_DIR

# code-server systemd 서비스 재시작
echo "🔄 Restarting code-server service..."
sudo systemctl daemon-reload
sudo systemctl restart code-server

echo "✅ VS Code Server is now secured with password authentication."
