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

variable "node_count" {
  description = "Number of EC2 instances"
  type        = number
  default     = 3
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "ssh_key_name" {
  description = "AWS key pair name for SSH access"
  type        = string
}
