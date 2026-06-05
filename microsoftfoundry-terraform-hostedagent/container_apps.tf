# ==============================================================================
# Container Apps Environment — Internal-only (MCP Subnet, AVM Module)
# Hosts the private MCP container app on the snet-mcp subnet behind an
# internal load balancer. Workload profile is Consumption.
# ==============================================================================

module "container_apps_env" {
  source  = "Azure/avm-res-app-managedenvironment/azurerm"
  version = "0.4.0"

  name                = local.container_apps_env_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  enable_telemetry    = var.enable_telemetry
  tags                = local.default_tags

  # VNet injection — internal load balancer only, no public ingress
  infrastructure_subnet_id       = module.vnet.subnets["snet-mcp"].resource_id
  internal_load_balancer_enabled = true

  # Consumption workload profile
  workload_profile = [{
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }]

  # Log Analytics integration
  log_analytics_workspace_customer_id        = module.log_analytics.resource.workspace_id
  log_analytics_workspace_primary_shared_key = module.log_analytics.resource.primary_shared_key
}
