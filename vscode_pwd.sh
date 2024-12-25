#!/bin/bash

# 사용자로부터 비밀번호 입력받기
read -s -p "Enter the password to set: " PASSWORD
echo

# 비밀번호 확인을 위한 입력
read -s -p "Confirm the password: " PASSWORD_CONFIRM
echo

# 두 비밀번호가 일치하는지 확인
if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
    echo "Passwords do not match. Exiting."
    exit 1
fi

# 비밀번호 해시 생성 (SHA-256)
PASSWORD_HASH=$(echo -n "$PASSWORD" | sha256sum | awk '{print $1}')

# code-server 설정 파일 경로
CONFIG_DIR="/home/ec2-user/.config/code-server"
CONFIG_FILE="$CONFIG_DIR/config.yaml"

# code-server 설정 파일 업데이트
mkdir -p $CONFIG_DIR
cat <<EOF > $CONFIG_FILE
bind-addr: 0.0.0.0:8888
auth: password
hashed-password: $PASSWORD_HASH
cert: false
EOF

# 설정 파일 권한 설정
chown -R ec2-user:ec2-user $CONFIG_DIR

# systemd 데몬 다시 로드 및 code-server 서비스 재시작
sudo systemctl daemon-reload
sudo systemctl restart code-server

echo "VS Code Server password authentication is now enabled."
