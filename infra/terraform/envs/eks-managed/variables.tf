variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "cluster_name" {
  description = "Cluster name"
  type        = string
  default     = "eks-cluster"
}

variable "k8s_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.31"
}

variable "worker_instance_type" {
  description = "EC2 instance type for the Kubernetes worker nodes"
  type        = string
  default     = "c7i-flex.large"
}

variable "worker_count" {
  description = "Number of Kubernetes worker nodes"
  type        = number
  default     = 2
}

variable "ssh_key_name" {
  description = "AWS key pair name for SSH access to worker nodes"
  type        = string
}