# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------
output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.this.name
}

# -----------------------------------------------------------------------------
# Virtual Network
# -----------------------------------------------------------------------------
output "vnet_id" {
  description = "The resource ID of the virtual network"
  value       = module.vnet.resource_id
}

output "vnet_name" {
  description = "The name of the virtual network"
  value       = module.vnet.name
}

output "master_subnet_id" {
  description = "The resource ID of the ARO master subnet"
  value       = module.vnet.subnets["master"].resource_id
}

output "worker_subnet_id" {
  description = "The resource ID of the ARO worker subnet"
  value       = module.vnet.subnets["worker"].resource_id
}

output "pe_subnet_id" {
  description = "The resource ID of the private endpoints subnet"
  value       = module.vnet.subnets["pe"].resource_id
}

# -----------------------------------------------------------------------------
# ARO Cluster
# -----------------------------------------------------------------------------
output "aro_cluster_id" {
  description = "The resource ID of the ARO cluster"
  value       = module.aro.resource_id
}

output "aro_cluster_name" {
  description = "The name of the ARO cluster"
  value       = local.resource_names.aro
}

output "aro_console_url" {
  description = "The URL of the ARO cluster console (accessible via WireGuard VPN)"
  value       = module.aro.resource.properties.consoleProfile.url
}

output "aro_api_server_url" {
  description = "The URL of the ARO API server (accessible via WireGuard VPN)"
  value       = module.aro.resource.properties.apiserverProfile.url
}

# -----------------------------------------------------------------------------
# Managed Identities
# -----------------------------------------------------------------------------
output "aro_cluster_identity_id" {
  description = "The resource ID of the ARO cluster managed identity"
  value       = azurerm_user_assigned_identity.cluster.id
}

output "aro_platform_identity_ids" {
  description = "Map of platform workload identity names to their resource IDs"
  value = {
    for name, identity in azurerm_user_assigned_identity.platform : name => identity.id
  }
}

# -----------------------------------------------------------------------------
# NAT Gateway
# -----------------------------------------------------------------------------
output "nat_gateway_id" {
  description = "The resource ID of the NAT Gateway"
  value       = module.nat_gateway.resource_id
}

output "nat_gateway_public_ip" {
  description = "The public IP address of the NAT Gateway used for egress"
  value       = module.nat_gateway.public_ip_resource
}

# -----------------------------------------------------------------------------
# Log Analytics
# -----------------------------------------------------------------------------
output "log_analytics_workspace_id" {
  description = "The resource ID of the Log Analytics workspace"
  value       = module.log_analytics.resource_id
}

# -----------------------------------------------------------------------------
# WireGuard VPN Gateway
# -----------------------------------------------------------------------------
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
