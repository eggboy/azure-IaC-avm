data "azurerm_client_config" "current" {}

# Log Analytics Workspace
module "log_analytics" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "0.5.1"

  enable_telemetry    = var.enable_telemetry
  location            = azurerm_resource_group.this.location
  name                = "log-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.default_tags
}

# Application Insights
module "app_insights" {
  source  = "Azure/avm-res-insights-component/azurerm"
  version = "0.3.0"

  enable_telemetry    = var.enable_telemetry
  location            = azurerm_resource_group.this.location
  name                = "appi-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.default_tags
  workspace_id        = module.log_analytics.resource.id
}

# Key Vault
module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.10.2"

  enable_telemetry    = var.enable_telemetry
  location            = azurerm_resource_group.this.location
  name                = "kv-${var.project}-${var.environment}-${var.instance}"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.default_tags
  tenant_id           = data.azurerm_client_config.current.tenant_id

  network_acls = {
    default_action = "Deny"
    bypass         = "AzureServices"
  }

  private_endpoints = {
    vault = {
      name                          = "pep-kv-${local.name_prefix}"
      subnet_resource_id            = module.vnet.subnets["snet-pe"].resource_id
      private_dns_zone_resource_ids = [azurerm_private_dns_zone.vault.id]
    }
  }
}

# Storage Account
module "storage_account" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.6.7"

  account_replication_type = "LRS"
  account_tier             = "Standard"
  enable_telemetry         = var.enable_telemetry
  location                 = azurerm_resource_group.this.location
  name                     = "st${var.project}${var.environment}${var.instance}"
  resource_group_name      = azurerm_resource_group.this.name
  tags                     = local.default_tags

  network_rules = {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  private_endpoints = {
    blob = {
      name                          = "pep-st-blob-${local.name_prefix}"
      subnet_resource_id            = module.vnet.subnets["snet-pe"].resource_id
      subresource_name              = "blob"
      private_dns_zone_resource_ids = [azurerm_private_dns_zone.blob.id]
    }
    file = {
      name                          = "pep-st-file-${local.name_prefix}"
      subnet_resource_id            = module.vnet.subnets["snet-pe"].resource_id
      subresource_name              = "file"
      private_dns_zone_resource_ids = [azurerm_private_dns_zone.file.id]
    }
  }
}

# Azure Container Registry
module "container_registry" {
  source  = "Azure/avm-res-containerregistry-registry/azurerm"
  version = "0.5.1"

  enable_telemetry              = var.enable_telemetry
  location                      = azurerm_resource_group.this.location
  name                          = "cr${var.project}${var.environment}${var.instance}"
  network_rule_bypass_option    = "AzureServices"
  public_network_access_enabled = false
  resource_group_name           = azurerm_resource_group.this.name
  sku                           = "Premium"
  tags                          = local.default_tags

  private_endpoints = {
    registry = {
      name                          = "pep-cr-${local.name_prefix}"
      subnet_resource_id            = module.vnet.subnets["snet-pe"].resource_id
      private_dns_zone_resource_ids = [azurerm_private_dns_zone.acr.id]
    }
  }
}

# Grant ML workspace system-assigned identity AcrPull + AcrPush on the container registry
# so Azure ML can check ACR settings and build/push Docker images.
resource "azurerm_role_assignment" "acr_pull_workspace" {
  scope                            = module.container_registry.resource_id
  role_definition_name             = "AcrPull"
  principal_id                     = module.ml_workspace.system_assigned_mi_principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "acr_push_workspace" {
  scope                            = module.container_registry.resource_id
  role_definition_name             = "AcrPush"
  principal_id                     = module.ml_workspace.system_assigned_mi_principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
