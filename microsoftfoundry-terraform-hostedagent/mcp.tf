# ==============================================================================
# Private MCP server container app
#
# Source code, Dockerfile and build script live in ./mcp-server/.
#
# The container app runs on the same user-managed CAE used for any other
# private workloads (`module.container_apps_env`, see container_apps.tf).
# Because that CAE is internal-load-balancer-only, `external_enabled = true`
# here means "expose via the CAE's internal LB" — the resulting FQDN is only
# reachable from inside the VNet (and from WireGuard clients).
#
# Image pull: a dedicated UAMI (`mi-mcp-<workload>-<env>`) is granted AcrPull
# on the project ACR. The same UAMI is attached to the container app and used
# as the registries.identity reference, so no admin user / password secret is
# required.
# ==============================================================================

resource "azurerm_user_assigned_identity" "mcp" {
  name                = "mi-mcp-${var.workload}-${var.environment}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.default_tags
}

resource "azurerm_role_assignment" "mcp_acr_pull" {
  scope                = module.acr.resource_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.mcp.principal_id
  principal_type       = "ServicePrincipal"
}

module "mcp_container_app" {
  source  = "Azure/avm-res-app-containerapp/azurerm"
  version = "0.9.0"

  name                                  = "mcp-http-server"
  resource_group_name                   = azurerm_resource_group.this.name
  resource_group_id                     = azurerm_resource_group.this.id
  location                              = azurerm_resource_group.this.location
  container_app_environment_resource_id = module.container_apps_env.resource_id
  revision_mode                         = "Single"
  workload_profile_name                 = "Consumption"
  max_inactive_revisions                = 100
  enable_telemetry                      = var.enable_telemetry
  tags                                  = local.default_tags

  managed_identities = {
    user_assigned_resource_ids = [azurerm_user_assigned_identity.mcp.id]
  }

  registries = [{
    server   = module.acr.resource.login_server
    identity = azurerm_user_assigned_identity.mcp.id
  }]

  ingress = {
    external_enabled           = true
    target_port                = 8080
    transport                  = "auto"
    allow_insecure_connections = false
    traffic_weight = [{
      latest_revision = true
      percentage      = 100
    }]
  }

  template = {
    min_replicas = 1
    max_replicas = 1
    containers = [{
      name   = "mcp-http-server"
      image  = "${module.acr.resource.login_server}/multi-auth-mcp:${var.mcp_image_tag}"
      cpu    = 0.5
      memory = "1Gi"
    }]
  }

  depends_on = [azurerm_role_assignment.mcp_acr_pull]
}
