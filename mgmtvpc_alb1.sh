#!/bin/bash

# ALB 이름
ALB_NAME="mgmtvpc-InternetALB1"

# 대상 리전 (필요 시 수정)
REGION="ap-northeast-2"

# ALB의 ARN 조회
load_balancer_arn=$(aws elbv2 describe-load-balancers \
  --region "$REGION" \
  --query "LoadBalancers[?LoadBalancerName=='$ALB_NAME'].LoadBalancerArn" \
  --output text)

# ALB의 DNS 이름 조회
if [[ -n "$load_balancer_arn" ]]; then
  dns_name=$(aws elbv2 describe-load-balancers \
    --region "$REGION" \
    --load-balancer-arns "$load_balancer_arn" \
    --query "LoadBalancers[0].DNSName" \
    --output text)
  echo "ALB DNS Name: $dns_name"
else
  echo "ALB '$ALB_NAME' not found in region '$REGION'."
fi