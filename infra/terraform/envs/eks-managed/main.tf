provider "aws" {
  region = var.aws_region
}

locals {
  availability_zones = ["${var.aws_region}b", "${var.aws_region}c"]
}

data "aws_instances" "eks_worker_nodes" {
  depends_on = [aws_eks_node_group.node_group]
  instance_tags = {
    "eks:nodegroup-name" = aws_eks_node_group.node_group.node_group_name
  }
  instance_state_names = ["running"]
}
#================================================================
# NETWORKING
#================================================================

resource "aws_vpc" "eks_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { 
    Name = "${var.cluster_name}-eks-vpc" 
  }
}

# Two Public Subnets for Load Balancers
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.${count.index + 1}.0/24"
  availability_zone       = local.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = {
    Name                                        = "${var.cluster_name}-public-subnet-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared" # Tag 'shared' informuje EKS, że może używać tej podsieci.
    "kubernetes.io/role/elb"                    = "1"      # Tag wymagany przez AWS Load Balancer Controller do tworzenia publicznych ELB.
  }
}

# Two Private Subnets for EKS Worker Nodes
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.eks_vpc.id
  cidr_block        = "10.0.${10 + count.index + 1}.0/24" # np. 10.0.11.0/24 i 10.0.12.0/24
  availability_zone = local.availability_zones[count.index]
  tags = {
    Name                                        = "${var.cluster_name}-private-subnet-${count.index + 1}"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}

# Internet Gateway for Public Subnets
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.eks_vpc.id
  tags   = { Name = "${var.cluster_name}-igw" }
}

# EIP for NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
  depends_on = [aws_internet_gateway.gw]
}

# NAT Gateway for worker nodes
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "${var.cluster_name}-nat-gw" }
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.eks_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = { Name = "${var.cluster_name}-public-rt" }
}

# Private Route Table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.eks_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "${var.cluster_name}-private-rt" }
}

# Public Route Table Associations
resource "aws_route_table_association" "public" {
  count = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Route Table Associations
resource "aws_route_table_association" "private" {
  count = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

#================================================================
# SECURITY
#================================================================

# EC2 Security Group for Cluster Communication
resource "aws_security_group" "eks_cluster_sg" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "Main security group for EKS cluster communication"
  vpc_id      = aws_vpc.eks_vpc.id

  # Allow all traffic within the security group
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # Allow ingress HTTP and HTTPS traffic from anywhere
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

  # allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-cluster-sg"
  }
}

#================================================================
# IAM (Uprawnienia)
#================================================================

# IAM Role for EKS Cluster
resource "aws_iam_role" "eks_master_role" {
  name = "${var.cluster_name}-eks-master-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Standard Policy needed for EKS 
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_master_role.name
}

# Policy allowing EKS to manage VPC network resources.
resource "aws_iam_role_policy_attachment" "eks_service_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_master_role.name
}

# IAM Role for Worker Nodes
resource "aws_iam_role" "eks_worker_role" {
  name = "${var.cluster_name}-eks-worker-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Policies for Worker Nodes
resource "aws_iam_role_policy_attachment" "eks_worker_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_worker_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_worker_role.name
}

resource "aws_iam_role_policy_attachment" "ec2_container_registry_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_worker_role.name
}

resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.eks_worker_role.name
}

# SSM Policy for Worker Nodes
resource "aws_iam_role_policy_attachment" "ssm_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.eks_worker_role.name
}

#================================================================
# COMPUTE (EKS Cluster)
#================================================================

# EKS Cluster
resource "aws_eks_cluster" "cluster" {
  name     = var.cluster_name
  version  = var.k8s_version
  role_arn = aws_iam_role.eks_master_role.arn

  vpc_config {
    subnet_ids = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    security_group_ids = [aws_security_group.eks_cluster_sg.id]
    endpoint_public_access = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_service_policy
  ]
}

# Launch Template for EKS Worker Nodes
resource "aws_launch_template" "eks_workers" {
  name = "${var.cluster_name}-workers-lt"

  # Define root volume configuration
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 20
      volume_type = "gp3"
      delete_on_termination = true
    }
  }
  
  instance_type = var.worker_instance_type

  user_data = base64encode(<<EOF
Content-Type: multipart/mixed; boundary="==BOUNDARY=="
MIME-Version: 1.0

--==BOUNDARY==
Content-Type: text/x-shellscript
MIME-Version: 1.0

#!/bin/bash
/etc/eks/bootstrap.sh ${var.cluster_name} \
  --kubelet-extra-args "--max-pods=60"

--==BOUNDARY==--
EOF
  )

  # Tagging instances created from this template.
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.cluster_name}-eks-worker"
    }
  }
}

# EKS Node Group (Managed)
resource "aws_eks_node_group" "node_group" {
  cluster_name    = aws_eks_cluster.cluster.name
  node_group_name = "${var.cluster_name}-node-group"
  node_role_arn   = aws_iam_role.eks_worker_role.arn
  subnet_ids      = aws_subnet.private[*].id
  
  launch_template {
    id      = aws_launch_template.eks_workers.id
    version = aws_launch_template.eks_workers.latest_version
  }

  scaling_config {
    desired_size = var.worker_count
    max_size     = var.worker_count + 1
    min_size     = var.worker_count
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ec2_container_registry_read_only,
    aws_iam_role_policy_attachment.ebs_csi_policy,
    aws_iam_role_policy_attachment.ssm_policy
  ]
}

# =================================================================
# EKS ADD-ON: AWS EBS CSI Driver 
# =================================================================

data "tls_certificate" "eks" {
  url = aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}
# OIDC Provider for the EKS Cluster
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

# Dedicated IAM Role for the EBS CSI Driver
resource "aws_iam_role" "ebs_csi_driver_role" {
  name = "${var.cluster_name}-ebs-csi-driver-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${aws_iam_openid_connect_provider.eks.url}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          }
        }
      }
    ]
  })
}
    
resource "aws_iam_role_policy_attachment" "ebs_csi_driver_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_driver_role.name
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name = aws_eks_cluster.cluster.name
  addon_name   = "aws-ebs-csi-driver"

  service_account_role_arn = aws_iam_role.ebs_csi_driver_role.arn

  depends_on = [
    aws_iam_openid_connect_provider.eks,
    aws_iam_role_policy_attachment.ebs_csi_driver_policy_attachment,
  ]
}


#================================================================
# =================================================================
# EKS ADD-ON: Amazon CloudWatch Observability
# =================================================================

# Create the dedicated namespace required by the CloudWatch Observability add-on.
# Although the add-on can create this, defining it explicitly provides better control.
resource "kubernetes_namespace" "amazon_cloudwatch" {
  metadata {
    name = "amazon-cloudwatch"
  }
}

# IAM Role for the CloudWatch Observability Add-on (using IRSA).
resource "aws_iam_role" "cloudwatch_observability_role" {
  # We use a descriptive name for the role.
  name = "${var.cluster_name}-cw-observability-role"

  # The trust policy allows the Service Accounts created by the add-on
  # (within the 'amazon-cloudwatch' namespace) to assume this IAM role.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            # This condition restricts role assumption to Service Accounts in the specified namespace.
            "${aws_iam_openid_connect_provider.eks.url}:sub" = "system:serviceaccount:amazon-cloudwatch:*"
          }
        }
      }
    ]
  })
}

# Attach the required AWS-managed policy to the role.
# This policy grants the necessary permissions to send logs and metrics to CloudWatch.
resource "aws_iam_role_policy_attachment" "cloudwatch_observability_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.cloudwatch_observability_role.name
}

# Install and manage the Amazon CloudWatch Observability add-on for the EKS cluster.
resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name             = aws_eks_cluster.cluster.name
  # This is the official name for the add-on, supported on EKS 1.31.
  addon_name               = "amazon-cloudwatch-observability"
  
  addon_version            = "v4.6.0-eksbuild.1"

  # Associate the IAM role with the add-on's service account.
  service_account_role_arn = aws_iam_role.cloudwatch_observability_role.arn

  # Ensure that the add-on is created only after its dependencies are ready.
  depends_on = [
    aws_iam_openid_connect_provider.eks,
    aws_iam_role_policy_attachment.cloudwatch_observability_policy_attachment,
    kubernetes_namespace.amazon_cloudwatch,
  ]
}

# =================================================================
# CloudWatch Agent Configuration for Prometheus Scraping
# =================================================================

# This ConfigMap provides the scraping configuration for the CloudWatch Agent's
# Prometheus collector. It instructs the agent to discover and scrape Prometheus metrics.
resource "kubernetes_config_map" "cw_agent_prometheus_config" {
  metadata {
    # CORRECTED NAME: This is the specific name the agent looks for to configure Prometheus scraping.
    name      = "cwagent-prometheus-config"
    namespace = "amazon-cloudwatch"
  }

  data = {
    # This key ('prometheus.yaml') is also expected by the agent.
    # The content defines the Prometheus scraping jobs.
    "prometheus.yaml" = yamlencode({
      global = {
        scrape_interval = "15s"
        scrape_timeout  = "10s"
      }
      scrape_configs = [
        {
          job_name = "kubernetes-pods-prometheus"
          kubernetes_sd_configs = [{ role = "pod" }]
          # This relabeling configuration is key. It dynamically discovers pods
          # that are annotated for Prometheus scraping.
          relabel_configs = [
            # 1. Keep only pods that have the 'prometheus.io/scrape: "true"' annotation.
            {
              source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_scrape"]
              action        = "keep"
              regex         = "true"
            },
            # 2. Use the path from the 'prometheus.io/path' annotation (defaults to /metrics).
            {
              source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_path"]
              action        = "replace"
              target_label  = "__metrics_path__"
              regex         = "(.+)"
            },
            # 3. Construct the target address using the pod's IP and the port from 'prometheus.io/port'.
            {
              source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_port", "__meta_kubernetes_pod_ip"]
              action        = "replace"
              regex         = "([^:]+);(.+)"
              replacement   = "$2:$1"
              target_label  = "__address__"
            },
            # 4. Copy pod labels to the scraped metrics.
            {
              action = "labelmap"
              regex  = "__meta_kubernetes_pod_label_(.+)"
            },
            # 5. Add 'kubernetes_namespace' and 'kubernetes_pod_name' as labels.
            {
              source_labels = ["__meta_kubernetes_namespace"]
              action        = "replace"
              target_label  = "kubernetes_namespace"
            },
            {
              source_labels = ["__meta_kubernetes_pod_name"]
              action        = "replace"
              target_label  = "kubernetes_pod_name"
            }
          ]
        }
      ]
    })
  }

  # Ensure this ConfigMap is created only after the namespace and the add-on itself exist.
  depends_on = [
    kubernetes_namespace.amazon_cloudwatch,
    aws_eks_addon.cloudwatch_observability
  ]
}

data "aws_eks_cluster_auth" "cluster" {
  name = aws_eks_cluster.cluster.name
}

provider "kubernetes" {
  host                   = aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}
