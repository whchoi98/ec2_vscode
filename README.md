
# EC2 VS Code Server 배포 / EC2 VS Code Server Deployment

이 리포지토리는 기본 VPC에서 Amazon EC2 인스턴스에 VS Code 서버를 배포하는 AWS CloudFormation 템플릿을 포함하고 있습니다. 이 인스턴스는 AWS Systems Manager(SSM)를 지원하여 원격 관리가 가능하며, 개발에 필요한 도구들이 사전 설치되어 있습니다.

This repository contains an AWS CloudFormation template for deploying an EC2 instance with VS Code Server in a default VPC. The instance supports AWS Systems Manager (SSM) for remote management and comes pre-installed with necessary tools for development.

## 사전 요구 사항 / Prerequisites

1. AWS CLI가 설치되고 적절한 권한으로 구성되어 있어야 합니다.AWS CLI installed and configured with appropriate permissions.
2. IAM 역할 생성을 위한 AWS CloudFormation 권한이 필요합니다.AWS CloudFormation capabilities to create IAM roles.

## 시작하기 / Getting Started

### Clone the Repository

```bash
git clone https://github.com/whchoi98/ec2_vscode.git
```

### Pem Key (Option)
```
cd ~
ssh-keygen
mv ./ec2vscode ./ec2vscode.pem
chmod 400 ./ec2vscode.pem
aws ec2 import-key-pair --key-name "ec2vscode" --public-key-material fileb://./ec2vscode.pub
```

### CloudFormation 스택 배포 / Deploy the CloudFormation Stack

AWS CLI가 `ap-northeast-2` 리전으로 설정되어 있는지 확인하세요:

Ensure your AWS CLI is configured with the `ap-northeast-2` region:

```bash
source ~/.bash_profile
export AWS_REGION=ap-northeast-2
./defaultvpcid.sh
source ~/.bashrc
```

CloudFormation 스택 배포:

Deploy the CloudFormation stack:

```bash
aws cloudformation deploy \
  --template-file "~/ec2_vscode/ec2vscode.yaml" \
  --stack-name YourStackName \
  --parameter-overrides \
    InstanceType=t3.xlarge \
    AMIType=AmazonLinux2023 \
    DefaultVPCId=$DEFAULT_VPC_ID \
    PublicSubnetId=$PUBLIC_SUBNET_ID \
  --capabilities CAPABILITY_NAMED_IAM
```

## 파라미터 / Parameters

- **InstanceType**: 배포할 EC2 인스턴스 유형 (기본값: `t3.xlarge`)
- **AMIType** : 배포할 기본 Image (기본값 : `AmazonLinux2023`)
- **DefaultVPCId=$DEFAULT_VPC_ID** : Default VPC
- **PublicSubnetId=$PUBLIC_SUBNET_ID** : PublicAZ A

## 주의 사항 / Notes

- 템플릿은 Amazon Linux 2 또는 Amazon Linux 2023을 사용합니다.
- 배포된 EC2 인스턴스에는 원격 관리가 가능한 AWS Systems Manager(SSM)가 활성화되어 있습니다.
- The template uses Amazon Linux 2 or Amazon Linux 2023, depending on your selection.
- AWS Systems Manager (SSM) is enabled for the deployed EC2 instance, allowing for remote management.

## 보안 고려 사항 / Security Considerations

- 보안 그룹을 통해 EC2 인스턴스에 대한 접근을 제한하세요.
- 정기적으로 EC2 인스턴스를 업데이트하여 보안 패치를 적용하세요.

- Make sure to limit access to the EC2 instance via security groups.
- Regularly update your EC2 instance to apply security patches.

```
./vscode_ip.sh
```

```
$ ./vscode_ip.sh
EC2VSCodeServer = xxx.xxx.xxx.xxx
```

## EC2 VS Code Server로 연결 및 보안설정

EC2가 완전하게 배포된 후 3~5분 뒤에 브라우저에서 EC2VSCodeServer PublicIP:8080으로 접속합니다.
EC2VSCodeServer Terminal에서 아래를 실행합니다.

```bash
git clone https://github.com/whchoi98/ec2_vscode.git
```

```
cat ~/vscode_pwd.sh
```

Password 설정을 확인하고, 적절한 패스워드으로 변경한 이후 다시 실행합니다.

```
~/vscode_pwd.sh
```



더 자세한 구성 및 커스터마이징 옵션에 대해서는 이 리포지토리의 CloudFormation 템플릿을 참조하세요.

For more details on the configuration and customization options, refer to the CloudFormation template in this repository.


