output "aks_subnet_id" {
  description = "The resource ID of the AKS subnet"
  value       = module.vnet.subnets["aks"].resource_id
}

output "appgw_subnet_id" {
  description = "The resource ID of the Application Gateway subnet"
  value       = module.vnet.subnets["appgw"].resource_id
}

output "firewall_private_ip" {
  description = "The private IP address of the Azure Firewall"
  value       = module.firewall.resource.ip_configuration[0].private_ip_address
}

output "firewall_public_ip" {
  description = "The public IP address of the Azure Firewall"
  value       = azurerm_public_ip.firewall.ip_address
}

output "ilb_subnet_id" {
  description = "The resource ID of the ILB subnet"
  value       = module.vnet.subnets["ilb"].resource_id
}

output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.this.name
}

output "vnet_id" {
  description = "The resource ID of the virtual network"
  value       = module.vnet.resource_id
}

output "vnet_name" {
  description = "The name of the virtual network"
  value       = module.vnet.name
}

output "wireguard_subnet_id" {
  description = "The resource ID of the WireGuard subnet"
  value       = module.vnet.subnets["wireguard"].resource_id
}

output "wireguard_vm_id" {
  description = "The resource ID of the WireGuard VPN gateway VM"
  value       = module.wireguard_vm.resource_id
}

output "wireguard_vm_public_ip" {
  description = "Public IP of the WireGuard VPN gateway. Use as Endpoint in your client wg0.conf."
  value       = data.azurerm_public_ip.wireguard.ip_address
}

output "wireguard_admin_ssh_private_key" {
  description = "Auto-generated SSH private key for the WireGuard VM admin user (stored in Terraform state)"
  value       = module.wireguard_vm.admin_generated_ssh_private_key
  sensitive   = true
}

output "container_registry_id" {
  description = "The resource ID of the Azure Container Registry"
  value       = module.container_registry.resource_id
}

output "container_registry_login_server" {
  description = "The login server URL of the Azure Container Registry"
  value       = module.container_registry.resource.login_server
}

output "log_analytics_workspace_id" {
  description = "The resource ID of the Log Analytics workspace"
  value       = module.log_analytics.resource_id
}

output "pe_subnet_id" {
  description = "The resource ID of the private endpoints subnet"
  value       = module.vnet.subnets["pe"].resource_id
}

# -----------------------------------------------------------------------------
# AKS Outputs
# -----------------------------------------------------------------------------
output "aks_cluster_id" {
  description = "The resource ID of the AKS cluster"
  value       = module.aks.resource_id
}

output "aks_cluster_name" {
  description = "The name of the AKS cluster"
  value       = module.aks.name
}

output "aks_private_fqdn" {
  description = "The private FQDN of the AKS API server"
  value       = module.aks.private_fqdn
}

output "aks_oidc_issuer_url" {
  description = "The OIDC issuer URL for workload identity federation"
  value       = module.aks.oidc_issuer_profile_issuer_url
}

output "aks_kubelet_identity" {
  description = "The kubelet identity of the AKS cluster"
  value       = module.aks.kubelet_identity
}

output "aks_node_resource_group" {
  description = "The auto-created node resource group name"
  value       = module.aks.node_resource_group_name
}
