#!/bin/bash

# IAM 역할 이름과 인스턴스 프로파일 이름 정의
ROLE_NAME="EC2AdminAccessRole"
INSTANCE_PROFILE_NAME="EC2AdminAccessProfile"

# IAM 역할 생성
aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document file://<(echo '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}')

# IAM 역할에 AdministratorAccess 정책 연결
aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

# IAM 인스턴스 프로파일 생성
aws iam create-instance-profile \
  --instance-profile-name $INSTANCE_PROFILE_NAME

# 인스턴스 프로파일에 역할 추가
aws iam add-role-to-instance-profile \
  --instance-profile-name $INSTANCE_PROFILE_NAME \
  --role-name $ROLE_NAME

# EC2 인스턴스 ID 가져오기 (태그 이름이 EC2VSCodeServer인 경우)
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=EC2VSCodeServer" \
  --query "Reservations[*].Instances[*].InstanceId" \
  --output text)

# 인스턴스 프로파일을 EC2 인스턴스에 연결
aws ec2 associate-iam-instance-profile \
  --instance-id $INSTANCE_ID \
  --iam-instance-profile Name=$INSTANCE_PROFILE_NAME

echo "IAM Role and Instance Profile created and associated with EC2 instance ID: $INSTANCE_ID"