#!/bin/bash
# =============================================================================
# VSCode Server 배포 스크립트
#
# 인스턴스 타입 선택 (x86/ARM) 및 비밀번호 입력을 받아
# UserData 바이너리 URL을 아키텍처에 맞게 자동 변환 후 배포합니다.
#
# Usage:
#   bash ~/ec2_vscode/deploy_vscode.sh
#   bash ~/ec2_vscode/deploy_vscode.sh --stack-name my-stack
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_SRC="${SCRIPT_DIR}/vscode_server_secure.yaml"
STACK_NAME="${1:---stack-name}"

# 인자 파싱
if [ "$STACK_NAME" = "--stack-name" ]; then
    STACK_NAME=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --stack-name) STACK_NAME="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
fi

# =============================================================================
# 1. 스택 이름 입력
# =============================================================================
if [ -z "${STACK_NAME}" ]; then
    read -rp "Stack name [mgmt-vpc]: " STACK_NAME
    STACK_NAME="${STACK_NAME:-mgmt-vpc}"
fi
echo "Stack: ${STACK_NAME}"

# =============================================================================
# 2. Region 선택
# =============================================================================
DEFAULT_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo "ap-northeast-2")}"
echo ""
echo "=== Region 선택 ==="
echo ""
echo "    1) ap-northeast-2  (서울)"
echo "    2) ap-northeast-1  (도쿄)"
echo "    3) us-east-1       (버지니아)"
echo "    4) us-west-2       (오레곤)"
echo "    5) eu-west-1       (아일랜드)"
echo "    6) 직접 입력"
echo ""

while true; do
    read -rp "선택 [1-6, default=1 (${DEFAULT_REGION})]: " REGION_CHOICE
    REGION_CHOICE="${REGION_CHOICE:-1}"

    case "${REGION_CHOICE}" in
        1) AWS_REGION="ap-northeast-2" ; break ;;
        2) AWS_REGION="ap-northeast-1" ; break ;;
        3) AWS_REGION="us-east-1"      ; break ;;
        4) AWS_REGION="us-west-2"      ; break ;;
        5) AWS_REGION="eu-west-1"      ; break ;;
        6)
            read -rp "Region 입력 (예: ap-southeast-1): " AWS_REGION
            if [ -n "${AWS_REGION}" ]; then
                break
            else
                echo "ERROR: Region을 입력하세요."
            fi
            ;;
        *) echo "ERROR: 1~6 사이 숫자를 입력하세요." ;;
    esac
done
export AWS_REGION
echo "  Region: ${AWS_REGION}"

# =============================================================================
# 3. 비밀번호 입력
# =============================================================================
echo ""
while true; do
    read -rsp "VSCode Password (8자 이상): " VSCODE_PASSWORD
    echo ""
    if [ "${#VSCODE_PASSWORD}" -ge 8 ]; then
        read -rsp "Password 확인: " VSCODE_PASSWORD_CONFIRM
        echo ""
        if [ "${VSCODE_PASSWORD}" = "${VSCODE_PASSWORD_CONFIRM}" ]; then
            break
        else
            echo "ERROR: 비밀번호가 일치하지 않습니다. 다시 입력하세요."
        fi
    else
        echo "ERROR: 8자 이상 입력하세요."
    fi
done

# =============================================================================
# 4. 인스턴스 타입 선택
# =============================================================================
echo ""
echo "=== 인스턴스 타입 선택 ==="
echo ""
echo "  [x86_64 (Intel)]"
echo "    1) t3.large"
echo "    2) t3.xlarge"
echo "    3) t3.2xlarge"
echo "    4) m7i.xlarge"
echo "    5) m7i.2xlarge"
echo ""
echo "  [ARM64 (Graviton)]"
echo "    6) t4g.xlarge"
echo "    7) t4g.2xlarge"
echo "    8) m7g.xlarge"
echo "    9) m7g.2xlarge"
echo ""

while true; do
    read -rp "선택 [1-9, default=5 (m7i.2xlarge)]: " INSTANCE_CHOICE
    INSTANCE_CHOICE="${INSTANCE_CHOICE:-5}"

    case "${INSTANCE_CHOICE}" in
        1) INSTANCE_TYPE="t3.large";    ARCH="x86_64" ; break ;;
        2) INSTANCE_TYPE="t3.xlarge";   ARCH="x86_64" ; break ;;
        3) INSTANCE_TYPE="t3.2xlarge";  ARCH="x86_64" ; break ;;
        4) INSTANCE_TYPE="m7i.xlarge";  ARCH="x86_64" ; break ;;
        5) INSTANCE_TYPE="m7i.2xlarge"; ARCH="x86_64" ; break ;;
        6) INSTANCE_TYPE="t4g.xlarge";  ARCH="arm64"  ; break ;;
        7) INSTANCE_TYPE="t4g.2xlarge"; ARCH="arm64"  ; break ;;
        8) INSTANCE_TYPE="m7g.xlarge";  ARCH="arm64"  ; break ;;
        9) INSTANCE_TYPE="m7g.2xlarge"; ARCH="arm64"  ; break ;;
        *) echo "ERROR: 1~9 사이 숫자를 입력하세요." ;;
    esac
done

echo ""
echo "  Instance Type : ${INSTANCE_TYPE}"
echo "  Architecture  : ${ARCH}"

# =============================================================================
# 5. CloudFront Prefix List ID 조회
# =============================================================================
echo ""
echo "CloudFront Prefix List 조회 중..."
CF_PREFIX_LIST_ID=$(aws ec2 describe-managed-prefix-lists \
    --query "PrefixLists[?PrefixListName=='com.amazonaws.global.cloudfront.origin-facing'].PrefixListId" \
    --output text --region "${AWS_REGION}")

if [ -z "${CF_PREFIX_LIST_ID}" ] || [ "${CF_PREFIX_LIST_ID}" = "None" ]; then
    echo "ERROR: CloudFront origin-facing prefix list를 찾을 수 없습니다."
    exit 1
fi
echo "  Prefix List ID: ${CF_PREFIX_LIST_ID}"

# =============================================================================
# 6. 아키텍처별 AMI/바이너리 URL 설정
# =============================================================================
if [ "${ARCH}" = "arm64" ]; then
    AMI_SSM_PATH="/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-arm64"

    AWSCLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
    SSM_PLUGIN_URL="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_arm64/session-manager-plugin.rpm"
    CODESERVER_TAR="code-server-4.106.3-linux-arm64.tar.gz"
    CODESERVER_DIR="code-server-4.106.3-linux-arm64"
    CODESERVER_URL="https://github.com/coder/code-server/releases/download/v4.106.3/${CODESERVER_TAR}"
    CW_AGENT_URL="https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/arm64/latest/amazon-cloudwatch-agent.rpm"
    KIRO_URL="https://desktop-release.q.us-east-1.amazonaws.com/latest/kirocli-aarch64-linux.zip"
else
    AMI_SSM_PATH="/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"

    AWSCLI_URL="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
    SSM_PLUGIN_URL="https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm"
    CODESERVER_TAR="code-server-4.106.3-linux-amd64.tar.gz"
    CODESERVER_DIR="code-server-4.106.3-linux-amd64"
    CODESERVER_URL="https://github.com/coder/code-server/releases/download/v4.106.3/${CODESERVER_TAR}"
    CW_AGENT_URL="https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm"
    KIRO_URL="https://desktop-release.q.us-east-1.amazonaws.com/latest/kirocli-x86_64-linux.zip"
fi

# =============================================================================
# 7. 템플릿 복사 후 아키텍처별 URL 치환
# =============================================================================
TEMPLATE_WORK="/tmp/vscode_server_secure_${ARCH}.yaml"
cp "${TEMPLATE_SRC}" "${TEMPLATE_WORK}"

# AMI SSM 파라미터 경로
sed -i "s|al2023-ami-kernel-6.1-x86_64|$(basename "${AMI_SSM_PATH}")|g" "${TEMPLATE_WORK}"

# AWS CLI
sed -i "s|awscli-exe-linux-x86_64.zip|$(basename "${AWSCLI_URL}")|g" "${TEMPLATE_WORK}"

# SSM Plugin
sed -i "s|plugin/latest/linux_64bit/session-manager-plugin.rpm|plugin/latest/$(echo "${SSM_PLUGIN_URL}" | grep -oP 'latest/\K[^$]+')|g" "${TEMPLATE_WORK}"

# code-server (tar.gz 파일명 + 디렉토리명)
sed -i "s|code-server-4.106.3-linux-amd64\.tar\.gz|${CODESERVER_TAR}|g" "${TEMPLATE_WORK}"
sed -i "s|code-server-4.106.3-linux-amd64|${CODESERVER_DIR}|g" "${TEMPLATE_WORK}"

# CloudWatch Agent
sed -i "s|amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm|amazon_linux/${ARCH}/latest/amazon-cloudwatch-agent.rpm|g" "${TEMPLATE_WORK}"

# kiro-cli
sed -i "s|kirocli-x86_64-linux.zip|$(basename "${KIRO_URL}")|g" "${TEMPLATE_WORK}"

echo ""
echo "  Template: ${TEMPLATE_WORK} (${ARCH} 바이너리 적용)"

# =============================================================================
# 8. 배포 확인
# =============================================================================
echo ""
echo "============================================="
echo "  배포 요약"
echo "============================================="
echo "  Stack Name    : ${STACK_NAME}"
echo "  Region        : ${AWS_REGION}"
echo "  Instance Type : ${INSTANCE_TYPE} (${ARCH})"
echo "  AMI           : ${AMI_SSM_PATH}"
echo "  CF Prefix List: ${CF_PREFIX_LIST_ID}"
echo "============================================="
echo ""
read -rp "배포를 진행하시겠습니까? (y/N): " CONFIRM
if [[ ! "${CONFIRM}" =~ ^[yY]$ ]]; then
    echo "배포가 취소되었습니다."
    rm -f "${TEMPLATE_WORK}"
    exit 0
fi

# =============================================================================
# 9. CloudFormation 배포
# =============================================================================
echo ""
echo "CloudFormation 배포 중... (Stack: ${STACK_NAME})"

output=$(aws cloudformation deploy \
    --stack-name "${STACK_NAME}" \
    --template-file "${TEMPLATE_WORK}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
        "CloudFrontPrefixListId=${CF_PREFIX_LIST_ID}" \
        "InstanceType=${INSTANCE_TYPE}" \
        "VSCodePassword=${VSCODE_PASSWORD}" \
        "AmazonLinux2023AmiId=${AMI_SSM_PATH}" \
    --region "${AWS_REGION}" 2>&1) || {
    if echo "$output" | grep -qi "No changes to deploy"; then
        echo "스택에 변경 사항이 없습니다."
    else
        echo "ERROR: 배포 실패"
        echo "$output"
        rm -f "${TEMPLATE_WORK}"
        exit 1
    fi
}

# 임시 파일 정리
rm -f "${TEMPLATE_WORK}"

# =============================================================================
# 10. 결과 출력
# =============================================================================
echo ""
echo "============================================="
echo "  배포 완료"
echo "============================================="

aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontURL` || OutputKey==`VSCodeServerInstanceId` || OutputKey==`VSCodeServerPrivateIP`]' \
    --output table \
    --region "${AWS_REGION}" 2>/dev/null || true

CF_URL=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontURL`].OutputValue' \
    --output text --region "${AWS_REGION}" 2>/dev/null || echo "")

INSTANCE_ID=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --query 'Stacks[0].Outputs[?OutputKey==`VSCodeServerInstanceId`].OutputValue' \
    --output text --region "${AWS_REGION}" 2>/dev/null || echo "")

echo ""
echo "  접속 URL : ${CF_URL}"
echo "  SSM 접속 : aws ssm start-session --target ${INSTANCE_ID}"
echo ""
echo "  ※ CloudFront 배포 완료까지 3~5분 소요될 수 있습니다."
echo "  ※ EC2 UserData 설치 완료까지 추가 5~10분 소요됩니다."
echo ""
