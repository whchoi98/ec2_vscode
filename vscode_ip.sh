#!/bin/bash

# 태그 이름이 EC2VSCodeServer인 EC2 인스턴스의 Public IP 주소 가져오기
PUBLIC_IP=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=EC2VSCodeServer" \
    --query "Reservations[*].Instances[*].PublicIpAddress" \
    --output text)

# 결과 출력
echo "EC2VSCodeServer = $PUBLIC_IP"
