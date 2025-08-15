variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "cluster_name" {
  description = "Cluster name"
  type        = string
  default     = "selfhosted-k8s"
}

variable "master_instance_type" {
  description = "EC2 instance type for the Kubernetes master node"
  type        = string
  default     = "t3.medium"
}

variable "worker_instance_type" {
  description = "EC2 instance type for the Kubernetes worker nodes"
  type        = string
  default     = "t3.small"
}

variable "worker_count" {
  description = "Number of Kubernetes worker nodes"
  type        = number
  default     = 2
}

variable "ssh_key_name" {
  description = "AWS key pair name for SSH access"
  type        = string
}
