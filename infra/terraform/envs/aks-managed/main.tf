

# Configuration of the Azure provider
provider "azurerm" {
  features {}
  subscription_id = "XXXX"
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
}

# -----------------------------
# Resource Group
# -----------------------------
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
  tags = {
    environment = "terraform"
    project     = var.cluster_name
  }
}

# -----------------------------
# Log Analytics Workspace
# -----------------------------
resource "azurerm_log_analytics_workspace" "law" {
  name                = "${var.cluster_name}-law"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = { project = var.cluster_name }
}

# -----------------------------
# Virtual Network
# -----------------------------
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.cluster_name}-vnet"
  address_space       = [var.vnet_cidr]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = { project = var.cluster_name }
}

# -----------------------------
# Public Subnets
# -----------------------------
resource "azurerm_subnet" "public" {
  count                = length(var.public_subnet_prefixes)
  name                 = "${var.cluster_name}-public-${count.index + 1}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.public_subnet_prefixes[count.index]]
}

# -----------------------------
# Private Subnets
# -----------------------------
resource "azurerm_subnet" "private" {
  count                = length(var.private_subnet_prefixes)
  name                 = "${var.cluster_name}-private-${count.index + 1}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.private_subnet_prefixes[count.index]]
}

# -----------------------------
# Network Security Group (NSG)
# -----------------------------
resource "azurerm_network_security_group" "cluster_nsg" {
  name                = "${var.cluster_name}-nsg"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  security_rule {
    name                       = "allow-http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-https"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-intra-vnet"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.vnet_cidr
    destination_address_prefix = var.vnet_cidr
  }

  tags = { project = var.cluster_name }
}

# -----------------------------
# Association of NSG with private subnets
# -----------------------------
resource "azurerm_subnet_network_security_group_association" "private_nsg_assoc" {
  count                     = length(azurerm_subnet.private)
  subnet_id                 = azurerm_subnet.private[count.index].id
  network_security_group_id = azurerm_network_security_group.cluster_nsg.id
}

# -----------------------------
# AKS Cluster
# -----------------------------
resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "${var.cluster_name}-dns"
  kubernetes_version  = var.k8s_version

  default_node_pool {
    name            = "agentpool"
    node_count      = var.node_count
    vm_size         = var.node_vm_size
    vnet_subnet_id  = azurerm_subnet.private[0].id # Nodes in the private subnet
    max_pods        = 110
    type            = "VirtualMachineScaleSets"
    os_disk_size_gb = 30
  }

  linux_profile { # Added profile with SSH key
    admin_username = "azureuser"
    ssh_key {
      key_data = var.ssh_public_key
    }
  }

  identity {
    type = "SystemAssigned"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
    service_cidr      = "10.240.0.0/16"
    dns_service_ip    = "10.240.0.10"
  }

  api_server_access_profile {
    authorized_ip_ranges = ["0.0.0.0/0"]
  }

  tags = { project = var.cluster_name }

  depends_on = [
    azurerm_subnet_network_security_group_association.private_nsg_assoc
  ]
}

# ----------------------------------------------------
# KUBERNETES RESOURCES CREATED BY THE KUBERNETES PROVIDER
# ----------------------------------------------------

# Creates the 'azure-monitor' namespace
resource "kubernetes_namespace_v1" "azure_monitor" {
  metadata {
    name = "azure-monitor"
  }

  depends_on = [azurerm_kubernetes_cluster.aks]
}

# Creates ConfigMap inside the 'azure-monitor' namespace
resource "kubernetes_config_map_v1" "prometheus_scrape_config" {
  metadata {
    name      = "prometheus-scrape-config"
    namespace = kubernetes_namespace_v1.azure_monitor.metadata[0].name
  }

  data = {
    "prometheus.yaml" = <<-EOT
    global:
      scrape_interval: 15s
      scrape_timeout: 10s
    EOT
  }
}