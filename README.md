# EC2 VSCode Server - Secure Architecture

AWS CloudFormation을 사용하여 보안이 강화된 VSCode Server를 배포합니다.

## Architecture

![VSCode on EC2 Architecture](VSCode%20on%20EC2.png)

### 구성 요소

| 구성 요소 | CIDR / 설명 |
|---------|------------|
| VPC | 10.254.0.0/16 |
| Public Subnet A | 10.254.11.0/24 (ALB, NAT Gateway) |
| Public Subnet B | 10.254.12.0/24 (NAT Gateway) |
| Private Subnet A | 10.254.21.0/24 (VSCode Server EC2) |

### 트래픽 흐름

```
User -> CloudFront (HTTPS) -> ALB (HTTP:80) -> EC2 VSCode Server (TCP:8888)
```

### 보안 기능

- **CloudFront Prefix List**: ALB Security Group에서 CloudFront origin-facing IP만 허용
- **X-Custom-Secret Header**: CloudFront에서 ALB로 전달되는 커스텀 헤더로 직접 ALB 접근 차단
- **Private Subnet**: VSCode Server가 Private Subnet에 배치되어 직접 인터넷 노출 없음
- **SSM VPC Endpoints**: Private Subnet에서 SSM Session Manager 접근 지원

### EC2 User-Data 설치 항목

- SSM Agent
- AWS CLI Latest
- Node.js 20, Python3
- Kiro CLI
- Claude Code
- code-server v4.106.3
- Development Tools (Util)

## Prerequisites

- AWS CLI 설치 및 적절한 권한 구성
- CloudFormation IAM 역할 생성 권한

## Quick Start

### 1. Repository Clone

```bash
git clone https://github.com/whchoi98/ec2_vscode.git
```

### 2. VSCode Server Password 설정

```bash
# VSCode Server Password를 변경하세요 (최소 8자 이상)
export VSCODE_PASSWORD='1234Qwer'
```

### 3. CloudFront Prefix List ID 조회

```bash
CF_PREFIX_LIST_ID=$(aws ec2 describe-managed-prefix-lists \
  --query "PrefixLists[?PrefixListName=='com.amazonaws.global.cloudfront.origin-facing'].PrefixListId" \
  --output text)
echo "CloudFront Prefix List ID = $CF_PREFIX_LIST_ID"
```

### 4. CloudFormation 스택 배포

```bash
aws cloudformation deploy \
  --stack-name mgmt-vpc \
  --template-file ~/ec2_vscode/vscode_server_secure.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    CloudFrontPrefixListId=$CF_PREFIX_LIST_ID \
    VSCodePassword="$VSCODE_PASSWORD" \
  --region ap-northeast-2
```

### 5. 접속

CloudFormation Output에 CloudFront URL이 자동 포함되어 있습니다. 배포 시 설정한 패스워드를 입력하세요.

```bash
aws cloudformation describe-stacks \
  --stack-name mgmt-vpc \
  --query "Stacks[0].Outputs[?OutputKey=='CloudFrontURL'].OutputValue" \
  --output text \
  --region ap-northeast-2
```

## Parameters

| 파라미터 | 기본값 | 설명 |
|---------|-------|------|
| CloudFrontPrefixListId | (필수) | CloudFront origin-facing managed prefix list ID |
| AvailabilityZoneA | ap-northeast-2a | 첫 번째 가용 영역 |
| AvailabilityZoneB | ap-northeast-2b | 두 번째 가용 영역 |
| VPCCIDRBlock | 10.254.0.0/16 | VPC CIDR |
| PublicSubnetABlock | 10.254.11.0/24 | Public Subnet A CIDR |
| PublicSubnetBBlock | 10.254.12.0/24 | Public Subnet B CIDR |
| PrivateSubnetABlock | 10.254.21.0/24 | Private Subnet A CIDR |
| PrivateSubnetBBlock | 10.254.22.0/24 | Private Subnet B CIDR |
| InstanceType | m7i.2xlarge | EC2 인스턴스 타입 |
| VSCodePassword | (필수) | VSCode Server 비밀번호 (최소 8자) |

## Outputs

| Output | 설명 |
|--------|------|
| CloudFrontURL | VSCode Server 접속 URL (HTTPS) |
| VSCodeServerInstanceId | EC2 Instance ID (SSM 접속용) |
| VSCodeServerPrivateIP | EC2 Private IP |

## SSM 접속

```bash
aws ssm start-session --target <VSCodeServerInstanceId>
```

## 스택 삭제

```bash
aws cloudformation delete-stack --stack-name mgmt-vpc --region ap-northeast-2
```

## Claude Code + Amazon Bedrock 설정 스크립트

VSCode Server 배포 후 Claude Code를 Amazon Bedrock과 연동하기 위한 설정 스크립트입니다.

### 1. setup-vscode-extension-settings.sh

**용도**: VS Code Extension (code-server 웹 UI) 환경에서 Claude Code 설정

code-server의 `settings.json`에 Claude Code Extension 설정을 추가합니다.

**설정 항목**:
- CLAUDE_CODE_USE_BEDROCK: Bedrock 사용 활성화
- AWS_BEARER_TOKEN_BEDROCK: Bedrock 인증 토큰
- ANTHROPIC_MODEL: Claude Opus 4.5
- ANTHROPIC_SMALL_FAST_MODEL: Claude Haiku 4.5

**사용 방법**:

```bash
# VSCode Server (code-server) 터미널에서 실행
git clone https://github.com/whchoi98/ec2_vscode.git
chmod +x ~/ec2_vscode/setup-vscode-extension-settings.sh
~/ec2_vscode/setup-vscode-extension-settings.sh

# AWS_BEARER_TOKEN_BEDROCK 값 입력 프롬프트가 표시됩니다
# 설정 완료 후 code-server 재시작
sudo systemctl restart code-server
```

### 2. setup-claude-bedrock-bashrc.sh

**용도**: CLI (터미널) 환경에서 Claude Code 사용을 위한 bashrc 환경 변수 설정

`~/.bashrc`에 Claude Code + Bedrock 환경 변수를 추가합니다.

**설정 항목**:
- ANTHROPIC_API_KEY: Anthropic API 키
- AWS_BEARER_TOKEN_BEDROCK: Bedrock 인증 토큰
- CLAUDE_CODE_USE_BEDROCK: Bedrock 사용 활성화
- ANTHROPIC_MODEL: Claude Opus 4.5
- ANTHROPIC_SMALL_FAST_MODEL: Claude Haiku 4.5

**사용 방법**:

```bash
# SSM 또는 터미널에서 실행
git clone https://github.com/whchoi98/ec2_vscode.git
chmod +x ~/ec2_vscode/setup-claude-bedrock-bashrc.sh
~/ec2_vscode/setup-claude-bedrock-bashrc.sh

# ANTHROPIC_API_KEY, AWS_BEARER_TOKEN_BEDROCK 값 입력 프롬프트가 표시됩니다
# 설정 적용
source ~/.bashrc

# Claude Code CLI 실행
claude
```

### 스크립트 선택 가이드

| 환경 | 스크립트 | 설명 |
|-----|---------|------|
| VS Code 웹 UI (브라우저) | `setup-vscode-extension-settings.sh` | Claude Code Extension 사용 |
| 터미널 / CLI | `setup-claude-bedrock-bashrc.sh` | Claude Code CLI 사용 |
