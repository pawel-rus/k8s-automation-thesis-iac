# outputs.tf

output "aks_cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "kube_config" {
  description = "Admin kubeconfig for AKS cluster"
  value       = azurerm_kubernetes_cluster.aks.kube_admin_config_raw
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID"
  value       = azurerm_log_analytics_workspace.law.id
}

output "node_resource_group" {
  description = "Resource group where AKS nodes are created"
  value       = azurerm_kubernetes_cluster.aks.node_resource_group
}