# -----------------------------------------------------------------------------
# Log Analytics Workspace (AVM)
# Used for AKS monitoring, Container Insights, and ACR diagnostics
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

  # Allow ingestion/query over public internet (no AMPLS)
  log_analytics_workspace_internet_ingestion_enabled = "true"
  log_analytics_workspace_internet_query_enabled     = "true"
}

# -----------------------------------------------------------------------------
# Private DNS Zone for ACR  (privatelink.azurecr.io)
# -----------------------------------------------------------------------------
resource "azurerm_private_dns_zone" "acr" {
  name                = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  name                  = "link-acr"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.acr.name
  virtual_network_id    = module.vnet.resource_id
}

# -----------------------------------------------------------------------------
# Azure Container Registry — Premium SKU with Private Endpoint (AVM)
# Public access disabled for private AKS cluster usage
# -----------------------------------------------------------------------------
module "container_registry" {
  source  = "Azure/avm-res-containerregistry-registry/azurerm"
  version = "0.5.1"

  location            = azurerm_resource_group.this.location
  name                = local.resource_names.container_registry
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags

  sku                           = "Premium"
  public_network_access_enabled = false
  zone_redundancy_enabled       = false
  network_rule_bypass_option    = "AzureServices"

  diagnostic_settings = {
    to_log_analytics = {
      name                  = "acr-diagnostics"
      workspace_resource_id = module.log_analytics.resource_id
    }
  }

  private_endpoints = {
    pe_acr = {
      name                          = "pe-cr-${local.name_prefix}-${var.location}-001"
      subnet_resource_id            = module.vnet.subnets["pe"].resource_id
      private_dns_zone_resource_ids = [azurerm_private_dns_zone.acr.id]
    }
  }
}
