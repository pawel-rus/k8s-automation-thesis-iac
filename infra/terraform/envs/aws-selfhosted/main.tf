provider "aws" {
  region = var.aws_region
}

locals {
  availability_zones = ["${var.aws_region}b", "${var.aws_region}c"]
}

#================================================================
# NETWORKING
#================================================================

# Virtual Private Cloud (VPC)
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.cluster_name}-vpc"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# Two public subnets for High Availability across two AZs 
# for resources that need direct internet access: master node and load balancers.
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  map_public_ip_on_launch = true
  availability_zone       = local.availability_zones[count.index]
  tags = {
    Name = "${var.cluster_name}-public-subnet-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "kubernetes.io/role/elb" = "1" # tag for load balancers
  }
}

# Private subnets for Worker Nodes

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${10 + count.index + 1}.0/24" # np. 10.0.11.0/24 i 10.0.12.0/24
  availability_zone = local.availability_zones[count.index]
  tags = {
    Name = "${var.cluster_name}-private-subnet-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "kubernetes.io/role/internal-elb" = "1" # tag for private load balancers
  }
}

# Internet Gateway for public subnets
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.cluster_name}-igw" }
}

# Elastic IP and a NAT Gateway for private subnets
resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.gw]
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id = aws_subnet.public[0].id # NAT Gateway in first public subnet
  tags = { Name = "${var.cluster_name}-nat-gw" }
}

# Route Table for public subnets, routing traffic through the IGW.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = { Name = "${var.cluster_name}-public-rt" }
}

# Route Table for private subnets, routing through the NAT Gateway.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "${var.cluster_name}-private-rt" }
}

# Associate the public route table with the public subnets.
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Associate the private route table with the private subnets.
resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

#================================================================
# SECURITY
#================================================================

# Security group for the Kubernetes nodes.
resource "aws_security_group" "k8s" {
  name        = "${var.cluster_name}-k8s-sg"
  description = "Security group for Kubernetes cluster nodes"
  vpc_id      = aws_vpc.main.id

  # Kubernetes API
  ingress {
    description = "K8s API Server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all internal traffic between nodes within the same security group
  ingress {
    description = "Node-to-node communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Allow inbound traffic from anywhere for standard web ports (HTTP/HTTPS).
  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Allow HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-k8s-sg"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

#================================================================
# IAM (Permissions for EC2 Instances)
#================================================================

# IAM role that EC2 instances can assume.
resource "aws_iam_role" "k8s_node_role" {
  name = "${var.cluster_name}-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
  tags = { Name = "${var.cluster_name}-node-role" }
}

# Attach the policy required for the AWS EBS CSI Driver to manage persistent volumes
resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.k8s_node_role.name
}

# Attach the policy required for AWS Systems Manager (SSM)
resource "aws_iam_role_policy_attachment" "ssm_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.k8s_node_role.name
}

#### MAKE SURE WE NEED THIS ####
# Attach the policy required for managing Elastic Load Balancers (for Ingress Controller)
# resource "aws_iam_role_policy_attachment" "elb_management_policy" {
#   policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess" 
#   role       = aws_iam_role.k8s_node_role.name
# }


# Policy for AWS Cloud Controller Manager
resource "aws_iam_policy" "ccm_policy" {
  name        = "${var.cluster_name}-ccm-policy"
  description = "IAM policy for the AWS Cloud Controller Manager"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "iam:CreateServiceLinkedRole", 
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:CreateSecurityGroup",
          "ec2:CreateTags",
          "ec2:DeleteSecurityGroup",
          "ec2:DeleteTags",
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInstances",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribePrefixLists",
          "ec2:DescribeRouteTables",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeTags",
          "ec2:DescribeVpcs",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:RevokeSecurityGroupIngress",
          # Permissions for Elastic Load Balancing
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DeleteRule",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeSSLPolicies",
          "elasticloadbalancing:DescribeTags",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:ModifyRule",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:RemoveTags",
          "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets",
          # Permissions for ACM (for SSL/TLS certificates)
          "acm:DescribeCertificate",
          "acm:ListCertificates",
          "waf-regional:GetWebACLForResource",
          "waf-regional:AssociateWebACL",
          "waf-regional:DisassociateWebACL",
          "shield:DescribeProtection",
          "shield:GetSubscriptionState",
          "shield:CreateProtection",
          "shield:DeleteProtection"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ccm_policy_attachment" {
  policy_arn = aws_iam_policy.ccm_policy.arn
  role       = aws_iam_role.k8s_node_role.name
}

# Create an instance profile to pass the IAM role to the EC2 instances.
resource "aws_iam_instance_profile" "k8s_node_profile" {
  name = "${var.cluster_name}-node-profile"
  role = aws_iam_role.k8s_node_role.name
}

#================================================================
# COMPUTE (EC2 Instances)
#================================================================

# Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Create an SSH key pair for emergency access via the EC2 console
resource "aws_key_pair" "deployer" {
  key_name   = var.ssh_key_name
  public_key = file(var.ssh_public_key_path)
}

# Master node instance in public subnet
resource "aws_instance" "master" {
  ami = data.aws_ami.ubuntu.id
  instance_type = var.master_instance_type
  key_name  = aws_key_pair.deployer.key_name
  subnet_id = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.k8s.id]
  iam_instance_profile   = aws_iam_instance_profile.k8s_node_profile.name
  
  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }
  
  tags = {
    Name = "${var.cluster_name}-master"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"

  }
}

# Worker nodes instances in private subnets
resource "aws_instance" "workers" {
  count         = var.worker_count
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.worker_instance_type
  key_name      = aws_key_pair.deployer.key_name
  subnet_id     = aws_subnet.private[count.index % 2].id # Distribute workers across private subnets
  vpc_security_group_ids = [aws_security_group.k8s.id]
  iam_instance_profile   = aws_iam_instance_profile.k8s_node_profile.name
  
  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.cluster_name}-worker-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}