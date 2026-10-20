#!/bin/bash
set -e
################################################################################
#                                                                              #
#   VSCode Server 인프라 배포 (CDK)                                             #
#   Deploy VSCode Server Infrastructure via CDK                                #
#                                                                              #
#   대화형으로 계정, 리전, VPC, 인스턴스 타입을 선택합니다.                        #
#   Interactively select account, region, VPC, and instance type.              #
#                                                                              #
#   CDK 프로젝트: infra-cdk/                                                    #
#   기본값: t4g.2xlarge (ARM64 Graviton)                                        #
#                                                                              #
################################################################################

# -- 색상 / Colors ------------------------------------------------------------
GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
BOLD='\033[1m'; DIM='\033[2m'
WORK_DIR="$(cd "$(dirname "$0")" && pwd)"
CDK_DIR="$WORK_DIR/infra-cdk"

echo ""
echo -e "${CYAN}=================================================================${NC}"
echo -e "${CYAN}   VSCode Server 인프라 배포 / Infrastructure Deployment${NC}"
echo -e "${CYAN}=================================================================${NC}"
echo ""

###############################################################################
#  [1/8] 사전 점검 / Pre-flight checks                                        #
###############################################################################
echo -e "${CYAN}[1/8] 사전 점검 / Pre-flight checks...${NC}"

for cmd in aws node npm; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${RED}오류: $cmd 를 찾을 수 없습니다 / ERROR: $cmd not found${NC}"
        exit 1
    fi
done
echo "  aws:  $(aws --version 2>&1 | head -1)"
echo "  node: $(node --version)  npm: $(npm --version)"

###############################################################################
#  [2/8] 계정 선택 / Account Selection                                         #
###############################################################################
echo ""
echo -e "${CYAN}[2/8] AWS 계정 선택 / Account Selection...${NC}"
echo ""

CURRENT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
CURRENT_USER=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || echo "")

if [ -n "$CURRENT_ACCOUNT" ]; then
    echo -e "  현재 자격 증명 / Current credentials:"
    echo "    계정 / Account: $CURRENT_ACCOUNT"
    echo "    사용자 / User:  $CURRENT_USER"
    echo ""
fi

echo -e "${BOLD}  계정 옵션 선택 / Select account option:${NC}"
echo ""
echo "    1) 현재 자격 증명 사용 / Use current credentials ($CURRENT_ACCOUNT)"
echo "    2) AWS 프로파일 선택 / Select AWS profile"
echo "    3) Access Key 직접 입력 / Enter Access Key manually"
echo ""
read -p "  번호 입력 / Enter number [1]: " ACCT_CHOICE
ACCT_CHOICE="${ACCT_CHOICE:-1}"

case "$ACCT_CHOICE" in
    2)
        echo ""
        echo -e "  ${CYAN}사용 가능한 프로파일 / Available profiles:${NC}"
        PROFILES=($(aws configure list-profiles 2>/dev/null || echo "default"))
        for i in "${!PROFILES[@]}"; do
            PROF_ACCT=$(aws sts get-caller-identity --profile "${PROFILES[$i]}" --query Account --output text 2>/dev/null || echo "?")
            printf "    %2d) %-20s (계정 / Account: %s)\n" $((i+1)) "${PROFILES[$i]}" "$PROF_ACCT"
        done
        echo ""
        read -p "  프로파일 번호 / Profile number: " PROF_CHOICE
        if [[ "$PROF_CHOICE" =~ ^[0-9]+$ ]] && [ "$PROF_CHOICE" -ge 1 ] && [ "$PROF_CHOICE" -le "${#PROFILES[@]}" ]; then
            export AWS_PROFILE="${PROFILES[$((PROF_CHOICE-1))]}"
            echo -e "  ${GREEN}프로파일 설정: $AWS_PROFILE${NC}"
        fi
        ;;
    3)
        echo ""
        read -p "  AWS Access Key ID: " INPUT_ACCESS_KEY
        read -sp "  AWS Secret Access Key: " INPUT_SECRET_KEY
        echo ""
        read -p "  리전 (예: ap-northeast-2): " INPUT_REGION

        aws configure set aws_access_key_id "$INPUT_ACCESS_KEY" --profile vscode-deploy
        aws configure set aws_secret_access_key "$INPUT_SECRET_KEY" --profile vscode-deploy
        aws configure set region "${INPUT_REGION:-ap-northeast-2}" --profile vscode-deploy
        export AWS_PROFILE="vscode-deploy"
        echo -e "  ${GREEN}자격 증명 설정 완료 / Credentials configured${NC}"
        ;;
    *)
        echo "  현재 자격 증명 사용 / Using current credentials"
        ;;
esac

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
if [ "$ACCOUNT_ID" = "unknown" ]; then
    echo -e "${RED}오류: AWS 계정 확인 실패 / ERROR: Cannot verify AWS account${NC}"
    exit 1
fi
echo -e "  ${GREEN}계정 확인 / Account verified: $ACCOUNT_ID${NC}"

###############################################################################
#  [3/8] 리전 선택 / Region Selection                                          #
###############################################################################
echo ""
echo -e "${CYAN}[3/8] 리전 선택 / Region Selection...${NC}"
echo ""
echo -e "${BOLD}  배포할 리전을 선택하세요 / Select deployment region:${NC}"
echo ""

REGIONS=(
    "ap-northeast-2:서울 / Seoul"
    "ap-northeast-1:도쿄 / Tokyo"
    "ap-northeast-3:오사카 / Osaka"
    "ap-southeast-1:싱가포르 / Singapore"
    "ap-southeast-2:시드니 / Sydney"
    "ap-south-1:뭄바이 / Mumbai"
    "us-east-1:버지니아 / N. Virginia"
    "us-east-2:오하이오 / Ohio"
    "us-west-2:오레곤 / Oregon"
    "eu-west-1:아일랜드 / Ireland"
    "eu-central-1:프랑크푸르트 / Frankfurt"
    "eu-west-2:런던 / London"
)

for i in "${!REGIONS[@]}"; do
    RCODE="${REGIONS[$i]%%:*}"
    RNAME="${REGIONS[$i]##*:}"
    MARKER=""
    [ "$RCODE" = "ap-northeast-2" ] && MARKER=" ${YELLOW}(기본값 / default)${NC}"
    printf "    %2d) %-20s %s" $((i+1)) "$RCODE" "$RNAME"
    echo -e "$MARKER"
done
echo ""
read -p "  번호 입력 / Enter number [1]: " REGION_CHOICE
REGION_CHOICE="${REGION_CHOICE:-1}"

if [[ "$REGION_CHOICE" =~ ^[0-9]+$ ]] && [ "$REGION_CHOICE" -ge 1 ] && [ "$REGION_CHOICE" -le "${#REGIONS[@]}" ]; then
    REGION="${REGIONS[$((REGION_CHOICE-1))]%%:*}"
else
    REGION="ap-northeast-2"
fi

echo -e "  ${GREEN}선택된 리전 / Selected: $REGION${NC}"
export AWS_DEFAULT_REGION="$REGION"

###############################################################################
#  [4/8] VPC 선택 / VPC Selection                                              #
###############################################################################
echo ""
echo -e "${CYAN}[4/8] VPC 선택 / VPC Selection...${NC}"
echo ""
echo -e "${BOLD}  VPC 옵션을 선택하세요 / Select VPC option:${NC}"
echo ""
echo "    1) 새 VPC 생성 / Create new VPC (10.254.0.0/16, 2 Public + 2 Private subnets)"
echo "    2) 기존 VPC 선택 / Use existing VPC from account"
echo ""
read -p "  번호 입력 / Enter number [1]: " VPC_CHOICE
VPC_CHOICE="${VPC_CHOICE:-1}"

USE_EXISTING_VPC="false"
EXISTING_VPC_ID=""
SKIP_VPC_ENDPOINTS="false"
VPC_CIDR=""
VPC_NAME=""

if [ "$VPC_CHOICE" = "1" ]; then
    echo ""
    read -p "  VPC 이름 / VPC Name [mgmt-vpc]: " VPC_NAME
    VPC_NAME="${VPC_NAME:-mgmt-vpc}"
fi

if [ "$VPC_CHOICE" = "2" ]; then
    echo ""
    echo -e "  ${CYAN}$REGION 리전의 VPC 목록 조회 중... / Listing VPCs in $REGION...${NC}"
    echo ""

    VPC_JSON=$(aws ec2 describe-vpcs --region "$REGION" --output json 2>/dev/null)
    VPC_COUNT=$(echo "$VPC_JSON" | python3 -c "import json,sys;print(len(json.load(sys.stdin).get('Vpcs',[])))")

    if [ "$VPC_COUNT" = "0" ]; then
        echo -e "  ${YELLOW}VPC가 없습니다. 새 VPC를 생성합니다.${NC}"
    else
        echo "$VPC_JSON" | python3 -c "
import json, sys
vpcs = json.load(sys.stdin).get('Vpcs', [])
for i, v in enumerate(vpcs):
    name = next((t['Value'] for t in v.get('Tags', []) if t['Key'] == 'Name'), '(이름 없음 / no name)')
    cidr = v.get('CidrBlock', '?')
    vid = v['VpcId']
    default = ' [기본 / default]' if v.get('IsDefault') else ''
    print('    {:2d}) {:25s} {:18s} {}{}'.format(i+1, vid, cidr, name, default))
"
        echo ""

        VPC_IDS=($(echo "$VPC_JSON" | python3 -c "import json,sys;[print(v['VpcId']) for v in json.load(sys.stdin).get('Vpcs',[])]"))

        read -p "  VPC 번호 선택 / Select VPC number: " VPC_SELECT

        if [[ "$VPC_SELECT" =~ ^[0-9]+$ ]] && [ "$VPC_SELECT" -ge 1 ] && [ "$VPC_SELECT" -le "${#VPC_IDS[@]}" ]; then
            EXISTING_VPC_ID="${VPC_IDS[$((VPC_SELECT-1))]}"
            USE_EXISTING_VPC="true"

            echo ""
            echo -e "  ${CYAN}$EXISTING_VPC_ID 서브넷 정보 / Subnet info:${NC}"
            aws ec2 describe-subnets --filters "Name=vpc-id,Values=$EXISTING_VPC_ID" \
                --region "$REGION" --output json 2>/dev/null | python3 -c "
import json, sys
subnets = json.load(sys.stdin).get('Subnets', [])
pub = [s for s in subnets if s.get('MapPublicIpOnLaunch')]
priv = [s for s in subnets if not s.get('MapPublicIpOnLaunch')]
print('    Public:  {} subnets'.format(len(pub)))
for s in pub:
    name = next((t['Value'] for t in s.get('Tags',[]) if t['Key']=='Name'), '')
    print('      {} {} {}'.format(s['SubnetId'], s['AvailabilityZone'], name))
print('    Private: {} subnets'.format(len(priv)))
for s in priv:
    name = next((t['Value'] for t in s.get('Tags',[]) if t['Key']=='Name'), '')
    print('      {} {} {}'.format(s['SubnetId'], s['AvailabilityZone'], name))

if len(pub) < 1 or len(priv) < 1:
    print()
    print('    WARNING: Need at least 1 public + 1 private subnet.')
"
        else
            echo -e "  ${YELLOW}잘못된 선택. 새 VPC 생성.${NC}"
        fi
    fi
fi

echo ""
if [ "$USE_EXISTING_VPC" = "true" ]; then
    echo -e "  ${GREEN}기존 VPC 사용 / Using existing VPC: $EXISTING_VPC_ID${NC}"

    VPC_CIDR=$(aws ec2 describe-vpcs --vpc-ids "$EXISTING_VPC_ID" --region "$REGION" \
        --query "Vpcs[0].CidrBlock" --output text 2>/dev/null || echo "10.0.0.0/8")
    echo "  VPC CIDR: $VPC_CIDR"

    echo -e "  ${CYAN}VPC Endpoint 확인 중... / Checking VPC Endpoints...${NC}"
    EXISTING_ENDPOINTS=$(aws ec2 describe-vpc-endpoints \
        --filters "Name=vpc-id,Values=$EXISTING_VPC_ID" "Name=vpc-endpoint-state,Values=available" \
        --query "VpcEndpoints[*].ServiceName" --output text --region "$REGION" 2>/dev/null || echo "")

    if echo "$EXISTING_ENDPOINTS" | grep -q "ssm" && \
       echo "$EXISTING_ENDPOINTS" | grep -q "ssmmessages" && \
       echo "$EXISTING_ENDPOINTS" | grep -q "ec2messages"; then
        SKIP_VPC_ENDPOINTS="true"
        echo -e "  ${GREEN}모든 SSM Endpoint 존재. 생성 건너뜀.${NC}"
    elif echo "$EXISTING_ENDPOINTS" | grep -qE "ssm|ssmmessages|ec2messages"; then
        SKIP_VPC_ENDPOINTS="true"
        echo -e "  ${YELLOW}일부 Endpoint 존재. 충돌 방지를 위해 CDK에서 건너뜁니다.${NC}"
    fi
else
    echo -e "  ${GREEN}새 VPC 생성 / Creating new VPC: ${VPC_NAME} (10.254.0.0/16)${NC}"
fi

###############################################################################
#  [5/8] 인스턴스 타입 선택 / Instance Type Selection                           #
###############################################################################
echo ""
echo -e "${CYAN}[5/8] 인스턴스 타입 선택 / Instance Type Selection...${NC}"
echo ""
echo -e "  ${BOLD}EC2 인스턴스 타입을 선택하세요 / Select EC2 instance type:${NC}"
echo ""

INSTANCE_TYPES=(
    "t4g.2xlarge:ARM64 Graviton, 8 vCPU, 32GB  (기본값 / default)"
    "t4g.xlarge:ARM64 Graviton, 4 vCPU, 16GB"
    "m7g.xlarge:ARM64 Graviton, 4 vCPU, 16GB"
    "m7g.2xlarge:ARM64 Graviton, 8 vCPU, 32GB"
    "r7g.xlarge:ARM64 Graviton, 4 vCPU, 32GB  (메모리 최적화 / mem-optimized)"
    "r7g.2xlarge:ARM64 Graviton, 8 vCPU, 64GB  (메모리 최적화 / mem-optimized)"
    "t3.xlarge:x86_64 Intel, 4 vCPU, 16GB"
    "t3.2xlarge:x86_64 Intel, 8 vCPU, 32GB"
    "m7i.xlarge:x86_64 Intel, 4 vCPU, 16GB"
    "m7i.2xlarge:x86_64 Intel, 8 vCPU, 32GB"
)

for i in "${!INSTANCE_TYPES[@]}"; do
    ITYPE="${INSTANCE_TYPES[$i]%%:*}"
    IDESC="${INSTANCE_TYPES[$i]##*:}"
    printf "    %2d) %-16s %s\n" $((i+1)) "$ITYPE" "$IDESC"
done
echo ""
echo "    0) 직접 입력 / Enter custom type"
echo ""
read -p "  번호 입력 / Enter number [1]: " ITYPE_CHOICE
ITYPE_CHOICE="${ITYPE_CHOICE:-1}"

if [ "$ITYPE_CHOICE" = "0" ]; then
    read -p "  인스턴스 타입 입력 / Enter instance type: " INSTANCE_TYPE
    INSTANCE_TYPE="${INSTANCE_TYPE:-t4g.2xlarge}"
elif [[ "$ITYPE_CHOICE" =~ ^[0-9]+$ ]]; then
    if [ "$ITYPE_CHOICE" -ge 1 ] && [ "$ITYPE_CHOICE" -le "${#INSTANCE_TYPES[@]}" ]; then
        INSTANCE_TYPE="${INSTANCE_TYPES[$((ITYPE_CHOICE-1))]%%:*}"
    else
        echo -e "  ${YELLOW}범위를 벗어난 번호입니다 / Number out of range, using default${NC}"
        INSTANCE_TYPE="t4g.2xlarge"
    fi
elif [[ "$ITYPE_CHOICE" =~ ^[a-z][a-z0-9-]*\.[a-z0-9]+$ ]]; then
    # 번호 대신 인스턴스 타입을 직접 입력한 경우 / Custom type typed directly
    INSTANCE_TYPE="$ITYPE_CHOICE"
else
    echo -e "  ${YELLOW}입력을 인식할 수 없습니다 / Unrecognized input, using default${NC}"
    INSTANCE_TYPE="t4g.2xlarge"
fi

echo -e "  ${GREEN}선택된 인스턴스 / Selected: $INSTANCE_TYPE${NC}"

###############################################################################
#  [6/8] CDK CLI 설치 / Install CDK CLI                                        #
###############################################################################
echo ""
echo -e "${CYAN}[6/8] CDK CLI 설치 / Install CDK CLI...${NC}"

if command -v cdk &>/dev/null; then
    echo "  이미 설치됨 / Already installed: $(cdk --version)"
else
    sudo npm install -g aws-cdk
    echo "  설치 완료 / Installed: $(cdk --version)"
fi

###############################################################################
#  [7/8] 설정 확인 / Confirm Configuration                                     #
###############################################################################
echo ""
echo -e "${CYAN}[7/8] 설정 확인 / Confirm Configuration...${NC}"

# CloudFront Prefix List
CF_PREFIX_LIST=$(aws ec2 describe-managed-prefix-lists \
    --filters "Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing" \
    --query "PrefixLists[0].PrefixListId" --output text --region "$REGION" 2>/dev/null || echo "")
if [ -z "$CF_PREFIX_LIST" ] || [ "$CF_PREFIX_LIST" = "None" ]; then
    echo -e "${RED}오류: CloudFront prefix list 없음 / Not found${NC}"
    exit 1
fi

# IAM Role 이름 (IAM은 전역) / IAM role name (IAM is global across regions)
STACK_NAME="VscodeServerStack"
BASE_ROLE_NAME="${STACK_NAME}-VSCode-Role"
ROLE_NAME_SUFFIX=""
CURRENT_ROLE=$(aws cloudformation describe-stack-resources --stack-name "$STACK_NAME" --region "$REGION" \
    --query "StackResources[?ResourceType=='AWS::IAM::Role' && ResourceStatus!='DELETE_COMPLETE'].PhysicalResourceId" \
    --output text 2>/dev/null | tr '\t' '\n' | grep "^${BASE_ROLE_NAME}" | head -1 || true)
if [ -n "$CURRENT_ROLE" ]; then
    # 이 리전 스택 업데이트: 기존 Role 이름 유지 / Updating this region's stack: keep its role name
    ROLE_NAME_SUFFIX="${CURRENT_ROLE#"$BASE_ROLE_NAME"}"
elif aws iam get-role --role-name "$BASE_ROLE_NAME" &>/dev/null; then
    # 다른 리전 스택이 기본 이름 사용 중 / Default name already taken by another region's stack
    ROLE_NAME_SUFFIX="-${REGION}"
    echo -e "  ${YELLOW}$BASE_ROLE_NAME 이(가) 다른 리전에서 사용 중 → ${BASE_ROLE_NAME}${ROLE_NAME_SUFFIX} 로 생성합니다.${NC}"
fi
ROLE_NAME="${BASE_ROLE_NAME}${ROLE_NAME_SUFFIX}"

# VSCode Password
VSCODE_PASSWORD="${VSCODE_PASSWORD:-}"
if [ -z "$VSCODE_PASSWORD" ]; then
    echo ""
    while true; do
        read -sp "  VSCode 비밀번호 (8자 이상) / Password (min 8 chars): " VSCODE_PASSWORD
        echo ""
        if [ ${#VSCODE_PASSWORD} -ge 8 ]; then
            read -sp "  비밀번호 확인 / Confirm password: " VSCODE_PASSWORD_CONFIRM
            echo ""
            if [ "$VSCODE_PASSWORD" = "$VSCODE_PASSWORD_CONFIRM" ]; then
                break
            else
                echo -e "  ${RED}비밀번호 불일치 / Passwords do not match${NC}"
            fi
        else
            echo -e "  ${RED}8자 이상 입력 / Must be 8+ characters${NC}"
        fi
    done
fi

echo ""
echo -e "  ${BOLD}┌─────────────────────────────────────────────────┐${NC}"
echo -e "  ${BOLD}│  배포 설정 요약 / Deployment Summary             │${NC}"
echo -e "  ${BOLD}├─────────────────────────────────────────────────┤${NC}"
echo "  │  계정 / Account:    $ACCOUNT_ID"
echo "  │  리전 / Region:     $REGION"
echo "  │  인스턴스 / Type:   $INSTANCE_TYPE"
echo "  │  CF Prefix List:    $CF_PREFIX_LIST"
echo "  │  IAM Role:          $ROLE_NAME"
if [ -n "$EXISTING_VPC_ID" ]; then
    echo "  │  VPC:               $EXISTING_VPC_ID (기존 / existing)"
else
    echo "  │  VPC:               새로 생성 / new ($VPC_NAME, 10.254.0.0/16)"
fi
echo "  │  비밀번호 / PW:     $(printf '*%.0s' $(seq 1 ${#VSCODE_PASSWORD}))"
echo -e "  ${BOLD}└─────────────────────────────────────────────────┘${NC}"
echo ""
read -p "  배포 시작? / Start deployment? (y/n) [y]: " CONFIRM
CONFIRM="${CONFIRM:-y}"
[ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ] && { echo "  취소 / Cancelled."; exit 0; }

###############################################################################
#  [8/8] CDK 빌드 + 부트스트랩 + 배포 / Build + Bootstrap + Deploy             #
###############################################################################
echo ""
echo -e "${CYAN}[8/8] CDK 빌드 + 배포 / Build + Deploy...${NC}"

cd "$CDK_DIR"
npm install --quiet
npx tsc
echo "  빌드 완료 / Build complete."

# CDK Bootstrap
cleanup_orphaned_bootstrap() {
    local BR="$1"
    local BUCKET_NAME="cdk-hnb659fds-assets-${ACCOUNT_ID}-${BR}"

    # ROLLBACK_COMPLETE 상태의 CDKToolkit 스택 삭제
    local STACK_STATUS
    STACK_STATUS=$(aws cloudformation describe-stacks --stack-name CDKToolkit --region "$BR" \
        --query "Stacks[0].StackStatus" --output text 2>/dev/null || echo "NONE")
    if [ "$STACK_STATUS" = "ROLLBACK_COMPLETE" ] || [ "$STACK_STATUS" = "DELETE_FAILED" ]; then
        echo -e "  ${YELLOW}비정상 CDKToolkit 스택 삭제 중 ($STACK_STATUS)...${NC}"
        aws cloudformation delete-stack --stack-name CDKToolkit --region "$BR" 2>/dev/null || true
        aws cloudformation wait stack-delete-complete --stack-name CDKToolkit --region "$BR" 2>/dev/null || true
    fi

    # 고아 S3 버킷 확인 및 정리
    if aws s3api head-bucket --bucket "$BUCKET_NAME" --region "$BR" 2>/dev/null; then
        echo -e "  ${YELLOW}고아 CDK 버킷 발견: $BUCKET_NAME${NC}"
        echo -e "  ${YELLOW}버킷 비우는 중...${NC}"
        aws s3 rm "s3://$BUCKET_NAME" --recursive --region "$BR" 2>/dev/null || true
        # 버전 관리된 객체 삭제
        local VERSIONS
        VERSIONS=$(aws s3api list-object-versions --bucket "$BUCKET_NAME" --region "$BR" \
            --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json 2>/dev/null || echo '{}')
        if echo "$VERSIONS" | python3 -c "import json,sys;d=json.load(sys.stdin);exit(0 if d.get('Objects') else 1)" 2>/dev/null; then
            echo "$VERSIONS" | aws s3api delete-objects --bucket "$BUCKET_NAME" --region "$BR" --delete file:///dev/stdin 2>/dev/null || true
        fi
        # DeleteMarkers도 정리
        local MARKERS
        MARKERS=$(aws s3api list-object-versions --bucket "$BUCKET_NAME" --region "$BR" \
            --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json 2>/dev/null || echo '{}')
        if echo "$MARKERS" | python3 -c "import json,sys;d=json.load(sys.stdin);exit(0 if d.get('Objects') else 1)" 2>/dev/null; then
            echo "$MARKERS" | aws s3api delete-objects --bucket "$BUCKET_NAME" --region "$BR" --delete file:///dev/stdin 2>/dev/null || true
        fi
        echo -e "  ${YELLOW}버킷 삭제 중...${NC}"
        aws s3api delete-bucket --bucket "$BUCKET_NAME" --region "$BR" 2>/dev/null || {
            echo -e "  ${RED}버킷 삭제 실패. 수동으로 삭제하세요: aws s3 rb s3://$BUCKET_NAME --force --region $BR${NC}"
        }
    fi

    # 고아 ECR 리포지토리 정리
    aws ecr delete-repository --repository-name "cdk-hnb659fds-container-assets-${ACCOUNT_ID}-${BR}" \
        --region "$BR" --force 2>/dev/null || true

    # 고아 SSM 파라미터 정리
    aws ssm delete-parameter --name "/cdk-bootstrap/hnb659fds/version" --region "$BR" 2>/dev/null || true
}

bootstrap_region() {
    local BR="$1"
    local STATUS
    STATUS=$(aws cloudformation describe-stacks --stack-name CDKToolkit --region "$BR" \
        --query "Stacks[0].StackStatus" --output text 2>/dev/null || echo "NONE")
    if [ "$STATUS" = "CREATE_COMPLETE" ] || [ "$STATUS" = "UPDATE_COMPLETE" ]; then
        echo "  $BR: 이미 부트스트랩됨 / bootstrapped ($STATUS)"
        return 0
    fi

    # 이전 bootstrap 잔여 리소스 정리
    cleanup_orphaned_bootstrap "$BR"

    echo "  $BR: 부트스트랩 중... / bootstrapping..."
    if ! npx cdk bootstrap "aws://$ACCOUNT_ID/$BR" --region "$BR" --force; then
        echo -e "${RED}오류: CDK 부트스트랩 실패 / ERROR: CDK bootstrap failed for $BR${NC}"
        echo ""
        echo "  수동 해결 방법 / Manual fix:"
        echo "    1. aws s3 rb s3://cdk-hnb659fds-assets-${ACCOUNT_ID}-${BR} --force --region $BR"
        echo "    2. aws cloudformation delete-stack --stack-name CDKToolkit --region $BR"
        echo "    3. 스크립트 재실행 / Re-run this script"
        exit 1
    fi

    # bootstrap 성공 확인
    local VERIFY
    VERIFY=$(aws ssm get-parameter --name "/cdk-bootstrap/hnb659fds/version" --region "$BR" \
        --query "Parameter.Value" --output text 2>/dev/null || echo "")
    if [ -z "$VERIFY" ]; then
        echo -e "${RED}오류: 부트스트랩 완료되었으나 SSM 파라미터 확인 실패${NC}"
        exit 1
    fi
    echo -e "  ${GREEN}$BR: 부트스트랩 완료 (version: $VERIFY)${NC}"
}

bootstrap_region "$REGION"

# CDK Context
CDK_CONTEXT=""
if [ -n "$EXISTING_VPC_ID" ]; then
    CDK_CONTEXT="-c useExistingVpc=true -c vpcId=$EXISTING_VPC_ID -c vpcCidr=${VPC_CIDR:-10.0.0.0/8}"
fi
if [ "$SKIP_VPC_ENDPOINTS" = "true" ]; then
    CDK_CONTEXT="$CDK_CONTEXT -c skipVpcEndpoints=true"
fi
if [ -n "$ROLE_NAME_SUFFIX" ]; then
    CDK_CONTEXT="$CDK_CONTEXT -c roleNameSuffix=$ROLE_NAME_SUFFIX"
fi

echo ""
echo -e "  ${CYAN}CDK 배포 중... (5-10분) / Deploying via CDK (5-10 min)...${NC}"
echo ""

npx cdk deploy "$STACK_NAME" \
    --parameters InstanceType="$INSTANCE_TYPE" \
    --parameters VSCodePassword="$VSCODE_PASSWORD" \
    --parameters CloudFrontPrefixListId="$CF_PREFIX_LIST" \
    --parameters ExistingVpcId="${EXISTING_VPC_ID}" \
    --parameters VpcName="${VPC_NAME:-mgmt-vpc}" \
    $CDK_CONTEXT \
    --require-approval never \
    --region "$REGION" 2>&1

###############################################################################
#  결과 출력 / Output Results                                                  #
###############################################################################
echo ""
echo -e "${CYAN}결과 파싱 / Parsing outputs...${NC}"

OUTPUTS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" --region "$REGION" \
    --query "Stacks[0].Outputs" --output json 2>/dev/null || echo "[]")

parse_output() {
    echo "$OUTPUTS" | python3 -c "import json,sys;o={i['OutputKey']:i['OutputValue'] for i in json.load(sys.stdin)};print(o.get('$1','N/A'))" 2>/dev/null || echo "N/A"
}

CF_URL=$(parse_output "CloudFrontURL")
INSTANCE_ID=$(parse_output "InstanceId")
VPC_ID=$(parse_output "VPCId")
OUT_ROLE_NAME=$(parse_output "EC2RoleName")
[ "$OUT_ROLE_NAME" != "N/A" ] && ROLE_NAME="$OUT_ROLE_NAME"

echo ""
echo -e "${GREEN}=================================================================${NC}"
echo -e "${GREEN}   배포 완료 / Deployment Complete${NC}"
echo -e "${GREEN}=================================================================${NC}"
echo ""
echo "  스택 / Stack:       $STACK_NAME"
echo "  리전 / Region:      $REGION"
echo "  계정 / Account:     $ACCOUNT_ID"
echo "  인스턴스 / Instance: $INSTANCE_ID ($INSTANCE_TYPE)"
echo "  VPC:                $VPC_ID"
echo ""
echo -e "  ${BOLD}┌─────────────────────────────────────────────────┐${NC}"
echo -e "  ${BOLD}│  접속 방법 / How to Access                       │${NC}"
echo -e "  ${BOLD}├─────────────────────────────────────────────────┤${NC}"
echo -e "  │                                                 │"
echo -e "  │  ${GREEN}방법 1: VSCode Server (브라우저)${NC}               │"
echo -e "  │  URL: ${BOLD}${CF_URL}${NC}"
echo -e "  │  비밀번호 / Password: (설정한 비밀번호)          │"
echo -e "  │                                                 │"
echo -e "  │  ${GREEN}방법 2: SSM Session Manager (터미널)${NC}          │"
echo -e "  │  aws ssm start-session \\                       │"
echo -e "  │    --target $INSTANCE_ID \\      │"
echo -e "  │    --region $REGION                     │"
echo -e "  │                                                 │"
echo -e "  ${BOLD}└─────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "  ${BOLD}┌─────────────────────────────────────────────────────────────┐${NC}"
echo -e "  ${BOLD}│  EC2 IAM Role                                               │${NC}"
echo -e "  ${BOLD}├─────────────────────────────────────────────────────────────┤${NC}"
echo -e "  │                                                             │"
echo -e "  │  Role: ${GREEN}${ROLE_NAME}${NC}"
echo -e "  │                                                             │"
echo -e "  │  연결 정책 / Attached policies:                              │"
echo -e "  │    - AmazonSSMManagedInstanceCore  (SSM 접속)               │"
echo -e "  │    - CloudWatchAgentServerPolicy   (모니터링)                │"
echo -e "  │                                                             │"
echo -e "  │  ${YELLOW}AdministratorAccess 추가 (전체 권한):${NC}                      │"
echo -e "  │  aws iam attach-role-policy \\                              │"
echo -e "  │    --role-name ${ROLE_NAME} \\"
echo -e "  │    --policy-arn arn:aws:iam::aws:policy/AdministratorAccess │"
echo -e "  │                                                             │"
echo -e "  ${BOLD}└─────────────────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "  ${YELLOW}CloudFront 배포 완료까지 3-5분 소요될 수 있습니다.${NC}"
echo -e "  ${YELLOW}EC2 UserData 설치 완료까지 추가 5-10분 소요됩니다.${NC}"
echo ""
