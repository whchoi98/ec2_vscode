#!/bin/bash
# =============================================================================
# VSCode Server → 기존 VPC 배포 스크립트
#
# VPC 이름으로 기존 VPC를 찾고, Public/Private 서브넷을 자동 탐색하여
# VSCode Server를 배포합니다.
#
# Usage:
#   bash ~/ec2_vscode/deploy_vscode_existing_vpc.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_SRC="${SCRIPT_DIR}/vscode_existing_vpc.yaml"

# =============================================================================
# 1. Stack name
# =============================================================================
read -rp "Stack name [vscode-existing]: " STACK_NAME
STACK_NAME="${STACK_NAME:-vscode-existing}"
echo "  Stack: ${STACK_NAME}"

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
            if [ -n "${AWS_REGION}" ]; then break; fi
            echo "ERROR: Region을 입력하세요."
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
# 5. 기존 VPC 선택 (이름으로 검색)
# =============================================================================
echo ""
echo "=== VPC 선택 ==="
echo ""

# VPC 목록 조회 (Name 태그 포함)
VPC_LIST=$(aws ec2 describe-vpcs \
    --query 'Vpcs[*].[VpcId, CidrBlock, (Tags[?Key==`Name`].Value)[0] || `(no name)`]' \
    --output text --region "${AWS_REGION}" | sort -k3)

if [ -z "${VPC_LIST}" ]; then
    echo "ERROR: ${AWS_REGION} 리전에 VPC가 없습니다."
    exit 1
fi

echo "  사용 가능한 VPC 목록:"
echo ""
VPC_INDEX=0
declare -a VPC_IDS=()
declare -a VPC_CIDRS=()
declare -a VPC_NAMES=()

while IFS=$'\t' read -r vid vcidr vname; do
    VPC_INDEX=$((VPC_INDEX + 1))
    VPC_IDS+=("${vid}")
    VPC_CIDRS+=("${vcidr}")
    VPC_NAMES+=("${vname}")
    printf "    %2d) %-22s  %-18s  %s\n" "${VPC_INDEX}" "${vid}" "${vcidr}" "${vname}"
done <<< "${VPC_LIST}"

echo ""
while true; do
    read -rp "VPC 번호 또는 이름 검색: " VPC_INPUT
    # 번호 입력인 경우
    if [[ "${VPC_INPUT}" =~ ^[0-9]+$ ]] && [ "${VPC_INPUT}" -ge 1 ] && [ "${VPC_INPUT}" -le "${VPC_INDEX}" ]; then
        IDX=$((VPC_INPUT - 1))
        SELECTED_VPC_ID="${VPC_IDS[$IDX]}"
        SELECTED_VPC_CIDR="${VPC_CIDRS[$IDX]}"
        SELECTED_VPC_NAME="${VPC_NAMES[$IDX]}"
        break
    fi
    # vpc-id 직접 입력인 경우
    if [[ "${VPC_INPUT}" =~ ^vpc- ]]; then
        for i in "${!VPC_IDS[@]}"; do
            if [ "${VPC_IDS[$i]}" = "${VPC_INPUT}" ]; then
                SELECTED_VPC_ID="${VPC_IDS[$i]}"
                SELECTED_VPC_CIDR="${VPC_CIDRS[$i]}"
                SELECTED_VPC_NAME="${VPC_NAMES[$i]}"
                break 2
            fi
        done
        echo "ERROR: VPC ID '${VPC_INPUT}'를 찾을 수 없습니다."
        continue
    fi
    # 이름 검색인 경우
    MATCHES=()
    MATCH_INDICES=()
    for i in "${!VPC_NAMES[@]}"; do
        if [[ "${VPC_NAMES[$i],,}" == *"${VPC_INPUT,,}"* ]]; then
            MATCHES+=("${VPC_NAMES[$i]}")
            MATCH_INDICES+=("$i")
        fi
    done
    if [ "${#MATCHES[@]}" -eq 1 ]; then
        IDX="${MATCH_INDICES[0]}"
        SELECTED_VPC_ID="${VPC_IDS[$IDX]}"
        SELECTED_VPC_CIDR="${VPC_CIDRS[$IDX]}"
        SELECTED_VPC_NAME="${VPC_NAMES[$IDX]}"
        break
    elif [ "${#MATCHES[@]}" -gt 1 ]; then
        echo "  여러 VPC가 일치합니다:"
        for j in "${!MATCHES[@]}"; do
            IDX="${MATCH_INDICES[$j]}"
            printf "    %2d) %-22s  %-18s  %s\n" "$((IDX+1))" "${VPC_IDS[$IDX]}" "${VPC_CIDRS[$IDX]}" "${MATCHES[$j]}"
        done
        echo "  번호를 입력하세요."
        continue
    else
        echo "ERROR: '${VPC_INPUT}'와 일치하는 VPC가 없습니다."
    fi
done

echo ""
echo "  선택된 VPC: ${SELECTED_VPC_ID} (${SELECTED_VPC_NAME}) — ${SELECTED_VPC_CIDR}"

# =============================================================================
# 6. 서브넷 자동 탐색 및 선택
# =============================================================================
echo ""
echo "=== 서브넷 탐색 ==="
echo ""
echo "  ${SELECTED_VPC_ID} 의 서브넷을 조회합니다..."

# 전체 서브넷 조회
ALL_SUBNETS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${SELECTED_VPC_ID}" \
    --query 'Subnets[*].[SubnetId, AvailabilityZone, CidrBlock, MapPublicIpOnLaunch, (Tags[?Key==`Name`].Value)[0] || `(no name)`]' \
    --output text --region "${AWS_REGION}" | sort -k2)

if [ -z "${ALL_SUBNETS}" ]; then
    echo "ERROR: VPC에 서브넷이 없습니다."
    exit 1
fi

# Public/Private 분류
declare -a PUB_IDS=() PUB_AZS=() PUB_CIDRS=() PUB_NAMES=()
declare -a PRV_IDS=() PRV_AZS=() PRV_CIDRS=() PRV_NAMES=()

while IFS=$'\t' read -r sid saz scidr spublic sname; do
    if [ "${spublic}" = "True" ] || [ "${spublic}" = "true" ]; then
        PUB_IDS+=("${sid}"); PUB_AZS+=("${saz}"); PUB_CIDRS+=("${scidr}"); PUB_NAMES+=("${sname}")
    else
        # Public IP 자동 할당이 아니면 Private으로 분류
        # 추가로 라우트 테이블에서 IGW 확인 (더 정확한 판별)
        RT_ID=$(aws ec2 describe-route-tables \
            --filters "Name=association.subnet-id,Values=${sid}" \
            --query 'RouteTables[0].RouteTableId' \
            --output text --region "${AWS_REGION}" 2>/dev/null || echo "None")
        if [ "${RT_ID}" = "None" ] || [ -z "${RT_ID}" ]; then
            # 명시적 연결이 없으면 메인 라우트 테이블 확인
            RT_ID=$(aws ec2 describe-route-tables \
                --filters "Name=vpc-id,Values=${SELECTED_VPC_ID}" "Name=association.main,Values=true" \
                --query 'RouteTables[0].RouteTableId' \
                --output text --region "${AWS_REGION}" 2>/dev/null || echo "None")
        fi
        HAS_IGW=$(aws ec2 describe-route-tables \
            --route-table-ids "${RT_ID}" \
            --query "RouteTables[0].Routes[?GatewayId!=null && starts_with(GatewayId,'igw-')].GatewayId" \
            --output text --region "${AWS_REGION}" 2>/dev/null || echo "")
        if [ -n "${HAS_IGW}" ]; then
            PUB_IDS+=("${sid}"); PUB_AZS+=("${saz}"); PUB_CIDRS+=("${scidr}"); PUB_NAMES+=("${sname}")
        else
            PRV_IDS+=("${sid}"); PRV_AZS+=("${saz}"); PRV_CIDRS+=("${scidr}"); PRV_NAMES+=("${sname}")
        fi
    fi
done <<< "${ALL_SUBNETS}"

echo ""
echo "  Public 서브넷 (${#PUB_IDS[@]}개):"
for i in "${!PUB_IDS[@]}"; do
    printf "    %2d) %-26s  %-16s  %-18s  %s\n" "$((i+1))" "${PUB_IDS[$i]}" "${PUB_AZS[$i]}" "${PUB_CIDRS[$i]}" "${PUB_NAMES[$i]}"
done

echo ""
echo "  Private 서브넷 (${#PRV_IDS[@]}개):"
for i in "${!PRV_IDS[@]}"; do
    printf "    %2d) %-26s  %-16s  %-18s  %s\n" "$((i+1))" "${PRV_IDS[$i]}" "${PRV_AZS[$i]}" "${PRV_CIDRS[$i]}" "${PRV_NAMES[$i]}"
done

# --- Public Subnet 2개 선택 (ALB 용, 서로 다른 AZ 필요) ---
echo ""
if [ "${#PUB_IDS[@]}" -lt 2 ]; then
    echo "ERROR: ALB에 최소 2개의 Public 서브넷 (서로 다른 AZ)이 필요합니다."
    echo "  현재 Public 서브넷: ${#PUB_IDS[@]}개"
    exit 1
fi

# 2개 서로 다른 AZ의 Public 서브넷 자동 선택 시도
AUTO_PUB_A=""
AUTO_PUB_B=""
AUTO_AZ_A=""
for i in "${!PUB_IDS[@]}"; do
    if [ -z "${AUTO_PUB_A}" ]; then
        AUTO_PUB_A="${PUB_IDS[$i]}"
        AUTO_AZ_A="${PUB_AZS[$i]}"
    elif [ "${PUB_AZS[$i]}" != "${AUTO_AZ_A}" ]; then
        AUTO_PUB_B="${PUB_IDS[$i]}"
        break
    fi
done

if [ -n "${AUTO_PUB_A}" ] && [ -n "${AUTO_PUB_B}" ]; then
    echo "  ALB용 Public 서브넷 자동 선택:"
    echo "    A: ${AUTO_PUB_A}"
    echo "    B: ${AUTO_PUB_B}"
    read -rp "  이대로 사용하시겠습니까? (Y/n): " USE_AUTO_PUB
    USE_AUTO_PUB="${USE_AUTO_PUB:-Y}"
    if [[ "${USE_AUTO_PUB}" =~ ^[yY]$ ]]; then
        SELECTED_PUB_A="${AUTO_PUB_A}"
        SELECTED_PUB_B="${AUTO_PUB_B}"
    fi
fi

if [ -z "${SELECTED_PUB_A:-}" ]; then
    echo ""
    echo "  ALB용 Public 서브넷 A 번호를 선택하세요:"
    while true; do
        read -rp "  Public Subnet A 번호: " PUB_A_NUM
        if [[ "${PUB_A_NUM}" =~ ^[0-9]+$ ]] && [ "${PUB_A_NUM}" -ge 1 ] && [ "${PUB_A_NUM}" -le "${#PUB_IDS[@]}" ]; then
            SELECTED_PUB_A="${PUB_IDS[$((PUB_A_NUM-1))]}"
            SELECTED_PUB_A_AZ="${PUB_AZS[$((PUB_A_NUM-1))]}"
            break
        fi
        echo "  ERROR: 유효한 번호를 입력하세요."
    done

    echo "  ALB용 Public 서브넷 B 번호를 선택하세요 (다른 AZ):"
    while true; do
        read -rp "  Public Subnet B 번호: " PUB_B_NUM
        if [[ "${PUB_B_NUM}" =~ ^[0-9]+$ ]] && [ "${PUB_B_NUM}" -ge 1 ] && [ "${PUB_B_NUM}" -le "${#PUB_IDS[@]}" ]; then
            if [ "${PUB_AZS[$((PUB_B_NUM-1))]}" = "${SELECTED_PUB_A_AZ}" ]; then
                echo "  ERROR: Subnet A와 다른 AZ의 서브넷을 선택하세요."
                continue
            fi
            SELECTED_PUB_B="${PUB_IDS[$((PUB_B_NUM-1))]}"
            break
        fi
        echo "  ERROR: 유효한 번호를 입력하세요."
    done
fi

# --- Private Subnet 선택 (EC2 용) ---
echo ""
if [ "${#PRV_IDS[@]}" -eq 0 ]; then
    echo "ERROR: Private 서브넷을 찾을 수 없습니다."
    exit 1
elif [ "${#PRV_IDS[@]}" -eq 1 ]; then
    SELECTED_PRV_A="${PRV_IDS[0]}"
    echo "  EC2용 Private 서브넷 (자동): ${SELECTED_PRV_A} (${PRV_NAMES[0]})"
else
    echo "  EC2용 Private 서브넷 번호를 선택하세요:"
    while true; do
        read -rp "  Private Subnet 번호 [default=1]: " PRV_NUM
        PRV_NUM="${PRV_NUM:-1}"
        if [[ "${PRV_NUM}" =~ ^[0-9]+$ ]] && [ "${PRV_NUM}" -ge 1 ] && [ "${PRV_NUM}" -le "${#PRV_IDS[@]}" ]; then
            SELECTED_PRV_A="${PRV_IDS[$((PRV_NUM-1))]}"
            echo "  선택: ${SELECTED_PRV_A} (${PRV_NAMES[$((PRV_NUM-1))]})"
            break
        fi
        echo "  ERROR: 유효한 번호를 입력하세요."
    done
fi

# =============================================================================
# 7. SSM VPC Endpoint 확인
# =============================================================================
echo ""
echo "  SSM VPC Endpoint 확인 중..."
EXISTING_SSM_EP=$(aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=${SELECTED_VPC_ID}" "Name=service-name,Values=com.amazonaws.${AWS_REGION}.ssm" \
    --query 'VpcEndpoints[0].VpcEndpointId' \
    --output text --region "${AWS_REGION}" 2>/dev/null || echo "None")

if [ "${EXISTING_SSM_EP}" != "None" ] && [ -n "${EXISTING_SSM_EP}" ]; then
    echo "  SSM VPC Endpoint 이미 존재: ${EXISTING_SSM_EP}"
    CREATE_SSM="false"
else
    echo "  SSM VPC Endpoint 없음 → 생성합니다."
    CREATE_SSM="true"
fi

# =============================================================================
# 8. CloudFront Prefix List ID 조회
# =============================================================================
echo ""
echo "  CloudFront Prefix List 조회 중..."
CF_PREFIX_LIST_ID=$(aws ec2 describe-managed-prefix-lists \
    --query "PrefixLists[?PrefixListName=='com.amazonaws.global.cloudfront.origin-facing'].PrefixListId" \
    --output text --region "${AWS_REGION}")

if [ -z "${CF_PREFIX_LIST_ID}" ] || [ "${CF_PREFIX_LIST_ID}" = "None" ]; then
    echo "ERROR: CloudFront origin-facing prefix list를 찾을 수 없습니다."
    exit 1
fi
echo "  Prefix List ID: ${CF_PREFIX_LIST_ID}"

# =============================================================================
# 9. 아키텍처별 AMI/바이너리 URL 설정 + 템플릿 치환
# =============================================================================
if [ "${ARCH}" = "arm64" ]; then
    AMI_SSM_PATH="/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-arm64"
else
    AMI_SSM_PATH="/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
fi

TEMPLATE_WORK="/tmp/vscode_existing_vpc_${ARCH}.yaml"
cp "${TEMPLATE_SRC}" "${TEMPLATE_WORK}"

if [ "${ARCH}" = "arm64" ]; then
    # AMI
    sed -i "s|al2023-ami-kernel-6.1-x86_64|al2023-ami-kernel-6.1-arm64|g" "${TEMPLATE_WORK}"
    # AWS CLI
    sed -i "s|awscli-exe-linux-x86_64.zip|awscli-exe-linux-aarch64.zip|g" "${TEMPLATE_WORK}"
    # SSM Plugin
    sed -i "s|plugin/latest/linux_64bit/session-manager-plugin.rpm|plugin/latest/linux_arm64/session-manager-plugin.rpm|g" "${TEMPLATE_WORK}"
    # code-server
    sed -i "s|code-server-4.106.3-linux-amd64\.tar\.gz|code-server-4.106.3-linux-arm64.tar.gz|g" "${TEMPLATE_WORK}"
    sed -i "s|code-server-4.106.3-linux-amd64|code-server-4.106.3-linux-arm64|g" "${TEMPLATE_WORK}"
    # CloudWatch Agent
    sed -i "s|amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm|amazoncloudwatch-agent/amazon_linux/arm64/latest/amazon-cloudwatch-agent.rpm|g" "${TEMPLATE_WORK}"
    # kiro-cli
    sed -i "s|kirocli-x86_64-linux.zip|kirocli-aarch64-linux.zip|g" "${TEMPLATE_WORK}"
fi

echo "  Template: ${TEMPLATE_WORK} (${ARCH})"

# =============================================================================
# 10. 배포 확인
# =============================================================================
echo ""
echo "============================================="
echo "  배포 요약"
echo "============================================="
echo "  Stack Name      : ${STACK_NAME}"
echo "  Region          : ${AWS_REGION}"
echo "  Instance Type   : ${INSTANCE_TYPE} (${ARCH})"
echo "  AMI             : ${AMI_SSM_PATH}"
echo ""
echo "  VPC             : ${SELECTED_VPC_ID} (${SELECTED_VPC_NAME})"
echo "  VPC CIDR        : ${SELECTED_VPC_CIDR}"
echo "  Public Subnet A : ${SELECTED_PUB_A}"
echo "  Public Subnet B : ${SELECTED_PUB_B}"
echo "  Private Subnet  : ${SELECTED_PRV_A}"
echo ""
echo "  SSM Endpoints   : ${CREATE_SSM}"
echo "  CF Prefix List  : ${CF_PREFIX_LIST_ID}"
echo "============================================="
echo ""
read -rp "배포를 진행하시겠습니까? (y/N): " CONFIRM
if [[ ! "${CONFIRM}" =~ ^[yY]$ ]]; then
    echo "배포가 취소되었습니다."
    rm -f "${TEMPLATE_WORK}"
    exit 0
fi

# =============================================================================
# 11. CloudFormation 배포
# =============================================================================
echo ""
echo "CloudFormation 배포 중... (Stack: ${STACK_NAME})"

output=$(aws cloudformation deploy \
    --stack-name "${STACK_NAME}" \
    --template-file "${TEMPLATE_WORK}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
        "CloudFrontPrefixListId=${CF_PREFIX_LIST_ID}" \
        "VpcId=${SELECTED_VPC_ID}" \
        "VpcCIDR=${SELECTED_VPC_CIDR}" \
        "PublicSubnetA=${SELECTED_PUB_A}" \
        "PublicSubnetB=${SELECTED_PUB_B}" \
        "PrivateSubnetA=${SELECTED_PRV_A}" \
        "InstanceType=${INSTANCE_TYPE}" \
        "VSCodePassword=${VSCODE_PASSWORD}" \
        "AmazonLinux2023AmiId=${AMI_SSM_PATH}" \
        "CreateSSMEndpoints=${CREATE_SSM}" \
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

rm -f "${TEMPLATE_WORK}"

# =============================================================================
# 12. 결과 출력
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
