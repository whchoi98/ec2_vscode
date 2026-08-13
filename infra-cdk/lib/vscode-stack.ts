import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as elbv2_targets from 'aws-cdk-lib/aws-elasticloadbalancingv2-targets';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

export class VscodeStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly alb: elbv2.ApplicationLoadBalancer;
  public readonly distribution: cloudfront.Distribution;
  public readonly instance: ec2.Instance;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // -------------------------------------------------------
    // Parameters
    // -------------------------------------------------------
    const instanceType = new cdk.CfnParameter(this, 'InstanceType', {
      type: 'String',
      default: 't4g.2xlarge',
      allowedValues: [
        't4g.xlarge', 't4g.2xlarge',
        't3.large', 't3.xlarge', 't3.2xlarge',
        'm7g.xlarge', 'm7g.2xlarge',
        'r7g.xlarge', 'r7g.2xlarge',
        'm7i.xlarge', 'm7i.2xlarge',
      ],
      description: 'EC2 instance type for VSCode Server',
    });

    const vscodePassword = new cdk.CfnParameter(this, 'VSCodePassword', {
      type: 'String',
      noEcho: true,
      minLength: 8,
      description: 'Password for VSCode Server (minimum 8 characters)',
    });

    const cloudFrontPrefixListId = new cdk.CfnParameter(this, 'CloudFrontPrefixListId', {
      type: 'String',
      description: 'CloudFront origin-facing managed prefix list ID',
    });

    const vpcName = new cdk.CfnParameter(this, 'VpcName', {
      type: 'String',
      default: 'mgmt-vpc',
      description: 'Name tag for the VPC',
    });

    const existingVpcId = new cdk.CfnParameter(this, 'ExistingVpcId', {
      type: 'String',
      default: '',
      description: 'Existing VPC ID to use. Leave empty to create a new VPC.',
    });

    // -------------------------------------------------------
    // VPC: existing or new
    // -------------------------------------------------------
    if (this.node.tryGetContext('useExistingVpc') === 'true') {
      const vpcId = this.node.tryGetContext('vpcId') || '';
      this.vpc = ec2.Vpc.fromLookup(this, 'VPC', { vpcId }) as unknown as ec2.Vpc;
    } else {
      this.vpc = new ec2.Vpc(this, 'VPC', {
        ipAddresses: ec2.IpAddresses.cidr('10.254.0.0/16'),
        maxAzs: 2,
        natGateways: 1,
        subnetConfiguration: [
          {
            cidrMask: 24,
            name: 'Public',
            subnetType: ec2.SubnetType.PUBLIC,
          },
          {
            cidrMask: 24,
            name: 'Private',
            subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
          },
        ],
      });
      cdk.Tags.of(this.vpc).add('Name', vpcName.valueAsString);
    }

    // -------------------------------------------------------
    // Security Groups
    // -------------------------------------------------------
    const albSg = new ec2.SecurityGroup(this, 'ALBSecurityGroup', {
      vpc: this.vpc,
      securityGroupName: `${this.stackName}-ALB-SG`,
      description: 'ALB SG - CloudFront origin-facing only',
      allowAllOutbound: true,
    });

    new ec2.CfnSecurityGroupIngress(this, 'ALBIngressFromCloudFront', {
      groupId: albSg.securityGroupId,
      ipProtocol: 'tcp',
      fromPort: 80,
      toPort: 80,
      sourcePrefixListId: cloudFrontPrefixListId.valueAsString,
      description: 'HTTP from CloudFront origin-facing only',
    });

    const ec2Sg = new ec2.SecurityGroup(this, 'EC2SecurityGroup', {
      vpc: this.vpc,
      securityGroupName: `${this.stackName}-VSCode-SG`,
      description: 'VSCode EC2 SG - ALB traffic only',
      allowAllOutbound: true,
    });
    ec2Sg.addIngressRule(albSg, ec2.Port.tcp(8888), 'VSCode from ALB');

    // -------------------------------------------------------
    // SSM VPC Endpoints (skip if context skipVpcEndpoints=true)
    // -------------------------------------------------------
    if (this.node.tryGetContext('skipVpcEndpoints') !== 'true') {
      const ssmSg = new ec2.SecurityGroup(this, 'SSMSecurityGroup', {
        vpc: this.vpc,
        description: 'SSM VPC Endpoints SG - HTTPS from VPC CIDR',
        allowAllOutbound: true,
      });
      const vpcCidr = this.node.tryGetContext('useExistingVpc') === 'true'
        ? (this.node.tryGetContext('vpcCidr') || '10.0.0.0/8')
        : '10.254.0.0/16';
      ssmSg.addIngressRule(ec2.Peer.ipv4(vpcCidr), ec2.Port.tcp(443), 'HTTPS from VPC CIDR');

      new ec2.InterfaceVpcEndpoint(this, 'SSMEndpoint', {
        vpc: this.vpc,
        service: ec2.InterfaceVpcEndpointAwsService.SSM,
        subnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
        securityGroups: [ssmSg],
        privateDnsEnabled: true,
      });

      new ec2.InterfaceVpcEndpoint(this, 'SSMMessagesEndpoint', {
        vpc: this.vpc,
        service: ec2.InterfaceVpcEndpointAwsService.SSM_MESSAGES,
        subnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
        securityGroups: [ssmSg],
        privateDnsEnabled: true,
      });

      new ec2.InterfaceVpcEndpoint(this, 'EC2MessagesEndpoint', {
        vpc: this.vpc,
        service: ec2.InterfaceVpcEndpointAwsService.EC2_MESSAGES,
        subnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
        securityGroups: [ssmSg],
        privateDnsEnabled: true,
      });
    }

    // -------------------------------------------------------
    // IAM Role for EC2 (SSM + CloudWatch)
    // -------------------------------------------------------
    const ec2Role = new iam.Role(this, 'EC2Role', {
      roleName: `${this.stackName}-VSCode-Role`,
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('ServiceQuotasReadOnlyAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSageMakerReadOnly'),
      ],
      description: 'VSCode Server EC2 role - SSM, CloudWatch, quotas, and SageMaker read access',
    });

    // -------------------------------------------------------
    // EC2 Instance (Private Subnet)
    // -------------------------------------------------------
    const al2023Arm64 = ec2.MachineImage.latestAmazonLinux2023({
      cpuType: ec2.AmazonLinuxCpuType.ARM_64,
    });

    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      '#!/bin/bash',
      'set -euxo pipefail',
      'exec > >(tee /var/log/user-data.log) 2>&1',
      'echo "Starting user-data script at $(date)"',
      '',
      '# System update',
      'dnf update -y --allowerasing',
      'dnf install -y --allowerasing curl jq tar gzip python3 python3-pip',
      'pip3 install boto3 click bedrock-agentcore',
      '',
      '# Development tools (required for native npm modules on ARM64)',
      'dnf groupinstall -y "Development Tools" || dnf install -y gcc gcc-c++ make || echo "[WARN] Dev tools install failed"',
      '',
      '# Node.js 20',
      'curl -fsSL https://rpm.nodesource.com/setup_20.x | bash - || true',
      'dnf install -y nodejs || true',
      'if ! command -v node &>/dev/null || [ "$(node -v | cut -d. -f1 | tr -d v)" -lt 20 ]; then',
      '  curl -fsSL https://fnm.vercel.app/install | bash',
      '  export FNM_DIR="/root/.local/share/fnm"',
      '  export PATH="$FNM_DIR:$PATH"',
      '  eval "$(fnm env)"',
      '  fnm install 20 && fnm use 20',
      '  ln -sf "$(which node)" /usr/local/bin/node',
      '  ln -sf "$(which npm)" /usr/local/bin/npm',
      '  ln -sf "$(which npx)" /usr/local/bin/npx',
      'fi',
      'echo "Node.js version: $(node -v)"',
      '',
      '# AWS CLI v2',
      'ARCH=$(uname -m)',
      'if [ "$ARCH" = "aarch64" ]; then',
      '  curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o awscliv2.zip',
      'else',
      '  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip',
      'fi',
      'unzip -q awscliv2.zip && ./aws/install && rm -rf aws awscliv2.zip',
      '',
      '# SSM Plugin',
      'if [ "$ARCH" = "aarch64" ]; then',
      '  dnf install -y https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_arm64/session-manager-plugin.rpm',
      'else',
      '  dnf install -y https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm',
      'fi',
      '',
      '# Docker',
      'dnf install -y docker',
      'systemctl enable docker && systemctl start docker',
      'usermod -aG docker ec2-user',
      '',
      '# uv package manager',
      'curl -fsSL https://astral.sh/uv/install.sh | sh',
      '',
      '# code-server',
      'cd /tmp',
      'CS_VERSION="4.126.0"',
      'if [ "$ARCH" = "aarch64" ]; then',
      '  CS_PKG="code-server-${CS_VERSION}-linux-arm64"',
      'else',
      '  CS_PKG="code-server-${CS_VERSION}-linux-amd64"',
      'fi',
      'wget -q "https://github.com/coder/code-server/releases/download/v${CS_VERSION}/${CS_PKG}.tar.gz"',
      'tar -xzf "${CS_PKG}.tar.gz"',
      'mv "${CS_PKG}" /usr/local/lib/code-server',
      'ln -sf /usr/local/lib/code-server/bin/code-server /usr/local/bin/code-server',
      'rm -f "${CS_PKG}.tar.gz"',
      '',
      '# Configure code-server',
      'mkdir -p /home/ec2-user/.config/code-server',
      `cat > /home/ec2-user/.config/code-server/config.yaml <<CSEOF`,
      'bind-addr: 0.0.0.0:8888',
      'auth: password',
      `password: "${vscodePassword.valueAsString}"`,
      'cert: false',
      'CSEOF',
      'chown -R ec2-user:ec2-user /home/ec2-user/.config',
      '',
      '# code-server systemd service',
      'cat > /etc/systemd/system/code-server.service <<SVCEOF',
      '[Unit]',
      'Description=code-server',
      'After=network.target',
      '',
      '[Service]',
      'Type=simple',
      'User=ec2-user',
      'WorkingDirectory=/home/ec2-user',
      `Environment="PASSWORD=${vscodePassword.valueAsString}"`,
      'ExecStart=/usr/local/bin/code-server --config /home/ec2-user/.config/code-server/config.yaml',
      'Restart=always',
      'RestartSec=10',
      '',
      '[Install]',
      'WantedBy=multi-user.target',
      'SVCEOF',
      'systemctl daemon-reload && systemctl enable code-server && systemctl start code-server',
      '',
      '# Kiro CLI',
      'cd /home/ec2-user',
      'if [ "$ARCH" = "aarch64" ]; then',
      '  KIRO_ZIP="kirocli-aarch64-linux.zip"',
      'else',
      '  KIRO_ZIP="kirocli-x86_64-linux.zip"',
      'fi',
      'if curl --proto "=https" --tlsv1.2 -sSf "https://desktop-release.q.us-east-1.amazonaws.com/latest/${KIRO_ZIP}" -o kirocli.zip; then',
      '  unzip -q kirocli.zip',
      '  if [ -d "kirocli/bin" ]; then',
      '    chmod +x kirocli/bin/*',
      '    cp kirocli/bin/* /usr/local/bin/',
      '    rm -rf kirocli kirocli.zip',
      '    echo "kiro-cli installed successfully"',
      '  fi',
      'else',
      '  echo "[WARN] kiro-cli download failed"',
      'fi',
      '',
      '# Claude Code CLI',
      'npm install -g @anthropic-ai/claude-code || {',
      '  echo "[WARN] Claude Code CLI install failed, retrying..."',
      '  sleep 10',
      '  npm install -g @anthropic-ai/claude-code || echo "[WARN] Claude Code CLI install failed after retry"',
      '}',
      '',
      '# Ensure claude CLI is accessible system-wide',
      'NPM_PREFIX="$(npm prefix -g 2>/dev/null)"',
      'if [ -n "$NPM_PREFIX" ] && [ -f "$NPM_PREFIX/bin/claude" ] && ! command -v claude &>/dev/null; then',
      '  ln -sf "$NPM_PREFIX/bin/claude" /usr/local/bin/claude',
      'fi',
      '',
      '# Claude Code extension for code-server',
      'sudo -u ec2-user /usr/local/bin/code-server --install-extension Anthropic.claude-code || {',
      '  echo "[WARN] Extension install via gallery failed, trying VSIX..."',
      '  VSIX_URL=$(curl -s "https://open-vsx.org/api/Anthropic/claude-code/latest" | python3 -c "import sys,json; print(json.load(sys.stdin).get(\'files\',{}).get(\'download\',\'\'))" 2>/dev/null || echo "")',
      '  if [ -n "$VSIX_URL" ]; then',
      '    curl -sL "$VSIX_URL" -o /tmp/claude-code.vsix',
      '    sudo -u ec2-user /usr/local/bin/code-server --install-extension /tmp/claude-code.vsix || echo "[WARN] VSIX install also failed"',
      '    rm -f /tmp/claude-code.vsix',
      '  fi',
      '}',
      '',
      '# CloudWatch agent',
      'if [ "$ARCH" = "aarch64" ]; then',
      '  wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/arm64/latest/amazon-cloudwatch-agent.rpm || true',
      'else',
      '  wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm || true',
      'fi',
      '[ -f amazon-cloudwatch-agent.rpm ] && rpm -U ./amazon-cloudwatch-agent.rpm || true',
      'rm -f amazon-cloudwatch-agent.rpm',
      '',
      'echo "VSCode Server setup completed at $(date)"',
    );

    this.instance = new ec2.Instance(this, 'VSCodeServer', {
      instanceName: `${this.stackName}-VSCode-Server`,
      vpc: this.vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      instanceType: new ec2.InstanceType(instanceType.valueAsString),
      machineImage: al2023Arm64,
      securityGroup: ec2Sg,
      role: ec2Role,
      userData,
      blockDevices: [
        {
          deviceName: '/dev/xvda',
          volume: ec2.BlockDeviceVolume.ebs(100, {
            volumeType: ec2.EbsDeviceVolumeType.GP3,
            encrypted: true,
          }),
        },
      ],
    });

    // -------------------------------------------------------
    // Application Load Balancer (Internet-facing)
    // -------------------------------------------------------
    this.alb = new elbv2.ApplicationLoadBalancer(this, 'PublicALB', {
      loadBalancerName: `${this.stackName}-ALB`,
      vpc: this.vpc,
      internetFacing: true,
      securityGroup: albSg,
      idleTimeout: cdk.Duration.seconds(3600),
    });

    const customSecret = `${this.stackName}-secret-${this.account}`;

    // Listener: default 403, forward only when X-Custom-Secret matches
    const listener = this.alb.addListener('Listener80', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      defaultAction: elbv2.ListenerAction.fixedResponse(403, {
        contentType: 'text/plain',
        messageBody: 'Access Denied',
      }),
    });

    const vscodeTg = new elbv2.ApplicationTargetGroup(this, 'VSCodeTargetGroup', {
      targetGroupName: `${this.stackName}-TG`,
      vpc: this.vpc,
      port: 8888,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.INSTANCE,
      healthCheck: {
        path: '/',
        port: '8888',
        healthyHttpCodes: '200,302',
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
      stickinessCookieDuration: cdk.Duration.days(1),
    });
    vscodeTg.addTarget(new elbv2_targets.InstanceTarget(this.instance, 8888));

    listener.addAction('VSCodeRule', {
      priority: 1,
      conditions: [
        elbv2.ListenerCondition.httpHeader('X-Custom-Secret', [customSecret]),
      ],
      action: elbv2.ListenerAction.forward([vscodeTg]),
    });

    // -------------------------------------------------------
    // CloudFront Distribution
    // -------------------------------------------------------
    const albOrigin = new origins.HttpOrigin(this.alb.loadBalancerDnsName, {
      httpPort: 80,
      protocolPolicy: cloudfront.OriginProtocolPolicy.HTTP_ONLY,
      readTimeout: cdk.Duration.seconds(60),
      customHeaders: {
        'X-Custom-Secret': customSecret,
      },
    });

    this.distribution = new cloudfront.Distribution(this, 'CloudFrontDistribution', {
      comment: `VSCode Server distribution for ${this.stackName}`,
      defaultBehavior: {
        origin: albOrigin,
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
        cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
        originRequestPolicy: cloudfront.OriginRequestPolicy.ALL_VIEWER,
      },
      priceClass: cloudfront.PriceClass.PRICE_CLASS_ALL,
    });

    // -------------------------------------------------------
    // Outputs
    // -------------------------------------------------------
    new cdk.CfnOutput(this, 'VPCId', {
      value: this.vpc.vpcId,
      description: 'VPC ID',
      exportName: `${this.stackName}-VPC-ID`,
    });

    new cdk.CfnOutput(this, 'CloudFrontURL', {
      value: `https://${this.distribution.distributionDomainName}`,
      description: 'CloudFront Distribution URL (Use this to access VSCode)',
      exportName: `${this.stackName}-CloudFront-URL`,
    });

    new cdk.CfnOutput(this, 'PublicALBEndpoint', {
      value: `http://${this.alb.loadBalancerDnsName}`,
      description: 'Public ALB DNS Name (direct access denied - use CloudFront)',
      exportName: `${this.stackName}-Public-ALB-DNS`,
    });

    new cdk.CfnOutput(this, 'InstanceId', {
      value: this.instance.instanceId,
      description: 'VSCode Server EC2 Instance ID',
      exportName: `${this.stackName}-Instance-ID`,
    });

    new cdk.CfnOutput(this, 'PrivateIP', {
      value: this.instance.instancePrivateIp,
      description: 'VSCode Server Private IP',
    });

    new cdk.CfnOutput(this, 'SSMAccess', {
      value: `aws ssm start-session --target ${this.instance.instanceId}`,
      description: 'SSM Session Manager access command',
    });

    new cdk.CfnOutput(this, 'CustomHeaderSecret', {
      value: customSecret,
      description: 'Custom header secret for CloudFront -> ALB validation',
    });

    new cdk.CfnOutput(this, 'Architecture', {
      value: 'CloudFront (HTTPS) -> Internet-facing ALB (HTTP:80 + Custom Header) -> VSCode EC2 (HTTP:8888)',
      description: 'Network Architecture',
    });
  }
}
