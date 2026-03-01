output "application_insights_id" {
  description = "The ID of the Application Insights instance."
  value       = module.app_insights.resource_id
}

output "container_registry_id" {
  description = "The ID of the Container Registry."
  value       = module.container_registry.resource_id
}

output "key_vault_id" {
  description = "The ID of the Key Vault."
  value       = module.key_vault.resource_id
}

output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace."
  value       = module.log_analytics.resource.id
  sensitive   = true
}

output "ml_workspace_id" {
  description = "The ID of the Azure ML workspace."
  value       = module.ml_workspace.resource_id
}

output "resource_group_id" {
  description = "The ID of the resource group."
  value       = azurerm_resource_group.this.id
}

output "resource_group_name" {
  description = "The name of the resource group."
  value       = azurerm_resource_group.this.name
}

output "storage_account_id" {
  description = "The ID of the Storage Account."
  value       = module.storage_account.resource_id
}

output "user_assigned_identity_id" {
  description = "The ID of the User Assigned Managed Identity."
  value       = module.identity.resource_id
}

output "vnet_id" {
  description = "The ID of the virtual network."
  value       = module.vnet.resource_id
}

output "wireguard_admin_ssh_private_key" {
  description = "Auto-generated SSH private key for the WireGuard VM admin user (stored in Terraform state)."
  value       = module.wireguard_vm.admin_generated_ssh_private_key
  sensitive   = true
}

output "wireguard_vm_id" {
  description = "The resource ID of the WireGuard VPN gateway VM."
  value       = module.wireguard_vm.resource_id
}

output "wireguard_vm_public_ip" {
  description = "Public IP of the WireGuard VPN gateway. Use as Endpoint in your client wg0.conf."
  value       = data.azurerm_public_ip.wireguard.ip_address
}
