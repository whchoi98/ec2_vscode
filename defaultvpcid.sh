#!/bin/bash

# 기본 VPC ID를 가져옵니다.
DEFAULT_VPC_ID=$(aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text)

if [ -z "$DEFAULT_VPC_ID" ]; then
  echo "기본 VPC를 찾을 수 없습니다."
  exit 1
else
  echo "기본 VPC ID: $DEFAULT_VPC_ID"
fi

# 기본 VPC에 속한 첫 번째 퍼블릭 서브넷 ID를 가져옵니다.
PUBLIC_SUBNET_ID=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$DEFAULT_VPC_ID" "Name=defaultForAz,Values=true" --query "Subnets[0].SubnetId" --output text)

if [ -z "$PUBLIC_SUBNET_ID" ]; then
  echo "기본 VPC에 퍼블릭 서브넷을 찾을 수 없습니다."
  exit 1
else
  echo "퍼블릭 서브넷 ID: $PUBLIC_SUBNET_ID"
fi

# 환경 변수로 설정 및 export
export DEFAULT_VPC_ID=$DEFAULT_VPC_ID
export PUBLIC_SUBNET_ID=$PUBLIC_SUBNET_ID

# 환경 변수를 파일에 저장 (선택 사항)
echo "export DEFAULT_VPC_ID=$DEFAULT_VPC_ID" >> ~/.bashrc
echo "export PUBLIC_SUBNET_ID=$PUBLIC_SUBNET_ID" >> ~/.bashrc

# 새로 설정된 환경 변수를 현재 셸에 적용
source ~/.bashrc

echo "환경 변수 설정이 완료되었습니다."
echo "DEFAULT_VPC_ID: $DEFAULT_VPC_ID"
echo "PUBLIC_SUBNET_ID: $PUBLIC_SUBNET_ID"
source ~/.bashrc
