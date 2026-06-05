# ==============================================================================
# Log Analytics Workspace (AVM Module)
# ==============================================================================

module "log_analytics" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "0.5.1"

  location            = azurerm_resource_group.this.location
  name                = local.log_analytics_name
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.default_tags

  log_analytics_workspace_retention_in_days = 30
  log_analytics_workspace_sku               = "PerGB2018"

  # Private deployment — disable public ingestion and query
  log_analytics_workspace_internet_ingestion_enabled = "false"
  log_analytics_workspace_internet_query_enabled     = "false"
}

# ==============================================================================
# Application Insights (workspace-based, on the existing Log Analytics workspace)
# Wired to Foundry in Phase D via azapi_resource.conn_appinsights.
#
# internet_ingestion_enabled / internet_query_enabled are derived from the
# AMPLS access-mode variables so that flipping the AMPLS mode automatically
# flips the matching App Insights public-endpoint flag:
#   - var.ampls_query_access_mode    = "PrivateOnly" → internet_query_enabled    = false  (Phase E-2)
#   - var.ampls_ingestion_access_mode = "PrivateOnly" → internet_ingestion_enabled = false  (Phase E-3)
# Both default to "Open" so initial rollout (Phase E-1) does NOT close the
# public path — Foundry telemetry would otherwise be silently dropped before
# the AMPLS PE is reachable.
# ==============================================================================

resource "azurerm_application_insights" "this" {
  name                = local.app_insights_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  workspace_id        = module.log_analytics.resource.id
  application_type    = "web"
  tags                = local.default_tags

  daily_data_cap_in_gb = var.app_insights_daily_cap_gb
  # sampling_percentage left null (= 100%) initially. Revisit only if the daily
  # cap is repeatedly hit; tune from observed volume, not guesses.

  internet_ingestion_enabled    = var.ampls_ingestion_access_mode != "PrivateOnly"
  internet_query_enabled        = var.ampls_query_access_mode != "PrivateOnly"
  local_authentication_disabled = false
}

# ==============================================================================
# Azure Monitor Private Link Scope (AMPLS) + Scoped Services
# ==============================================================================
# AMPLS is a GLOBAL Azure resource — azurerm_monitor_private_link_scope does
# not take a `location` argument; the provider handles the global placement.
#
# Two scoped services attach Log Analytics + App Insights to the scope. AMPLS
# limits per docs: ≤50 resources, ≤300 scoped services per AMPLS, ≤10 AMPLS
# per resource. Well within bounds.
#
# Access modes default to "Open" (Phase E-1). Flip via tfvars per phase plan.
# Ref: https://learn.microsoft.com/en-us/azure/azure-monitor/logs/private-link-design
# ==============================================================================

resource "azurerm_monitor_private_link_scope" "this" {
  name                = "ampls-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.default_tags

  ingestion_access_mode = var.ampls_ingestion_access_mode
  query_access_mode     = var.ampls_query_access_mode
}

resource "azurerm_monitor_private_link_scoped_service" "log_analytics" {
  name                = "amplss-law-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.this.name
  scope_name          = azurerm_monitor_private_link_scope.this.name
  linked_resource_id  = module.log_analytics.resource.id
}

resource "azurerm_monitor_private_link_scoped_service" "app_insights" {
  name                = "amplss-appi-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.this.name
  scope_name          = azurerm_monitor_private_link_scope.this.name
  linked_resource_id  = azurerm_application_insights.this.id
}
