variable "location" {
  description = "Azure region (location)"
  type        = string
  default     = "westeurope"
}

variable "resource_group_name" {
  description = "Resource Group name"
  type        = string
  default     = "aks-rg"
}

variable "cluster_name" {
  description = "AKS cluster name"
  type        = string
  default     = "aks-cluster"
}

variable "k8s_version" {
  description = "Kubernetes version for AKS"
  type        = string
  default     = "1.32.9"
}

variable "node_count" {
  description = "Number of nodes in default node pool"
  type        = number
  default     = 2
}

variable "node_vm_size" {
  description = "Azure VM size for nodes"
  type        = string
  default     = "Standard_B2pls_v2"
}

variable "ssh_public_key" {
  description = "SSH public key for node VMs"
  type        = string
  default     = ""
}

variable "vnet_cidr" {
  description = "VNet address space"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_prefixes" {
  type = list(string)
  default = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_prefixes" {
  type = list(string)
  default = ["10.0.2.0/24", "10.0.3.0/24"]
}

variable "node_resource_group" {
  type    = string
  default = ""
}
