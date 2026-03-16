output "resource_group_name" {
  description = "The name of the resource group."
  value       = azurerm_resource_group.this.name
}

output "resource_group_id" {
  description = "The ID of the resource group."
  value       = azurerm_resource_group.this.id
}

output "vnet_id" {
  description = "The ID of the virtual network."
  value       = module.vnet.resource_id
}

output "ai_account_name" {
  description = "The name of the AI Services account."
  value       = azapi_resource.ai_account.name
}

output "ai_account_endpoint" {
  description = "The endpoint of the AI Services account."
  value       = azapi_resource.ai_account.output.properties.endpoint
}

output "ai_project_name" {
  description = "The name of the AI Foundry project."
  value       = azapi_resource.ai_project.name
}

output "apim_gateway_url" {
  description = "The gateway URL of the API Management instance."
  value       = var.enable_apim ? module.apim[0].apim_gateway_url : null
}

output "apim_id" {
  description = "The ID of the API Management instance."
  value       = var.enable_apim ? module.apim[0].resource_id : null
}

output "apim_name" {
  description = "The name of the API Management instance."
  value       = var.enable_apim ? module.apim[0].name : null
}

output "storage_account_id" {
  description = "The ID of the Storage Account."
  value       = module.storage.resource_id
}

output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace."
  value       = module.log_analytics.resource_id
}

output "container_apps_env_id" {
  description = "The ID of the Container Apps Environment."
  value       = module.container_apps_env.resource_id
}

output "container_apps_env_default_domain" {
  description = "The default domain of the internal Container Apps Environment."
  value       = module.container_apps_env.default_domain
}

output "ai_search_id" {
  description = "The ID of the AI Search Service."
  value       = module.search.resource_id
}

output "cosmosdb_id" {
  description = "The ID of the Cosmos DB account."
  value       = module.cosmos.resource_id
}

output "wireguard_vm_id" {
  description = "The resource ID of the WireGuard VPN gateway VM."
  value       = module.wireguard_vm.resource_id
}

output "wireguard_vm_public_ip" {
  description = "Public IP of the WireGuard VPN gateway. Use as Endpoint in your client wg0.conf."
  value       = data.azurerm_public_ip.wireguard.ip_address
}

output "wireguard_admin_ssh_private_key" {
  description = "Auto-generated SSH private key for the WireGuard VM admin user (stored in Terraform state)."
  value       = module.wireguard_vm.admin_generated_ssh_private_key
  sensitive   = true
}
