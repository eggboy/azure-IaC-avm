# -----------------------------------------------------------------------------
# Log Analytics Workspace (AVM)
# Used for ARO monitoring and diagnostics
# -----------------------------------------------------------------------------
module "log_analytics" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "0.5.1"

  location            = azurerm_resource_group.this.location
  name                = local.resource_names.log_analytics
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags

  log_analytics_workspace_retention_in_days = 30
  log_analytics_workspace_sku               = "PerGB2018"

  # Private cluster: disable public ingestion/query for full lockdown
  log_analytics_workspace_internet_ingestion_enabled = "false"
  log_analytics_workspace_internet_query_enabled     = "false"
}

# -----------------------------------------------------------------------------
# Private DNS Zone for ARO API Server (privatelink.<region>.aroapp.io)
# Required for private ARO clusters to resolve the API server endpoint
# within the VNet via WireGuard VPN or other connected networks.
# -----------------------------------------------------------------------------
resource "azurerm_private_dns_zone" "aro" {
  name                = "privatelink.${var.location}.aroapp.io"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "aro" {
  name                  = "link-aro"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.aro.name
  virtual_network_id    = module.vnet.resource_id
}

# -----------------------------------------------------------------------------
# Private DNS Zone for Log Analytics (privatelink.ods.opinsights.azure.com)
# Enables private ingestion of logs from within the VNet
# -----------------------------------------------------------------------------
resource "azurerm_private_dns_zone" "log_analytics_ods" {
  name                = "privatelink.ods.opinsights.azure.com"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "log_analytics_ods" {
  name                  = "link-log-ods"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.log_analytics_ods.name
  virtual_network_id    = module.vnet.resource_id
}

resource "azurerm_private_dns_zone" "log_analytics_oms" {
  name                = "privatelink.oms.opinsights.azure.com"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "log_analytics_oms" {
  name                  = "link-log-oms"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.log_analytics_oms.name
  virtual_network_id    = module.vnet.resource_id
}

resource "azurerm_private_dns_zone" "monitor" {
  name                = "privatelink.monitor.azure.com"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "monitor" {
  name                  = "link-monitor"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.monitor.name
  virtual_network_id    = module.vnet.resource_id
}

# -----------------------------------------------------------------------------
# Azure Monitor Private Link Scope (AMPLS)
# Groups Log Analytics and monitoring resources behind a single private endpoint
# -----------------------------------------------------------------------------
resource "azurerm_monitor_private_link_scope" "this" {
  name                = "ampls-${local.name_prefix}-${var.location}-001"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags

  ingestion_access_mode = "PrivateOnly"
  query_access_mode     = "PrivateOnly"
}

resource "azurerm_monitor_private_link_scoped_service" "log_analytics" {
  name                = "amplsservice-log"
  resource_group_name = azurerm_resource_group.this.name
  scope_name          = azurerm_monitor_private_link_scope.this.name
  linked_resource_id  = module.log_analytics.resource_id
}

# -----------------------------------------------------------------------------
# Private Endpoint for Azure Monitor Private Link Scope
# Routes all monitoring traffic through the VNet
# -----------------------------------------------------------------------------
resource "azurerm_private_endpoint" "monitor" {
  location            = azurerm_resource_group.this.location
  name                = "pe-ampls-${local.name_prefix}-${var.location}-001"
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = module.vnet.subnets["pe"].resource_id
  tags                = local.tags

  private_service_connection {
    is_manual_connection           = false
    name                           = "psc-ampls-${local.name_prefix}-${var.location}-001"
    private_connection_resource_id = azurerm_monitor_private_link_scope.this.id
    subresource_names              = ["azuremonitor"]
  }

  private_dns_zone_group {
    name = "default"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.log_analytics_ods.id,
      azurerm_private_dns_zone.log_analytics_oms.id,
      azurerm_private_dns_zone.monitor.id,
    ]
  }
}
