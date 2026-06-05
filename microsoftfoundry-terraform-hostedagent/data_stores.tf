# ==============================================================================
# Storage Account (AVM Module)
# ==============================================================================

module "storage" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.6.7"

  name                            = local.storage_name
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  account_tier                    = "Standard"
  account_replication_type        = local.storage_sku == "Standard_ZRS" ? "ZRS" : "GRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = false
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  enable_telemetry                = var.enable_telemetry
  tags                            = local.default_tags

  network_rules = {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  private_endpoints = {
    blob = {
      name                          = "pep-st-${local.name_prefix}"
      subnet_resource_id            = module.vnet.subnets["snet-pe"].resource_id
      subresource_name              = "blob"
      private_dns_zone_resource_ids = [module.dns_blob.resource_id]
    }
  }
}

# ==============================================================================
# AI Search Service (AVM Module)
# ==============================================================================

module "search" {
  source  = "Azure/avm-res-search-searchservice/azurerm"
  version = "0.2.0"

  name                          = local.ai_search_name
  resource_group_name           = azurerm_resource_group.this.name
  location                      = azurerm_resource_group.this.location
  sku                           = "standard"
  replica_count                 = 1
  partition_count               = 1
  public_network_access_enabled = false
  local_authentication_enabled  = false
  enable_telemetry              = var.enable_telemetry
  tags                          = local.default_tags

  managed_identities = {
    system_assigned = true
  }

  private_endpoints = {
    search = {
      name                          = "pep-srch-${local.name_prefix}"
      subnet_resource_id            = module.vnet.subnets["snet-pe"].resource_id
      private_dns_zone_resource_ids = [module.dns_search.resource_id]
    }
  }
}

# ==============================================================================
# Cosmos DB Account (AVM Module)
# ==============================================================================

module "cosmos" {
  source  = "Azure/avm-res-documentdb-databaseaccount/azurerm"
  version = "0.10.0"

  name                          = local.cosmos_db_name
  resource_group_name           = azurerm_resource_group.this.name
  location                      = azurerm_resource_group.this.location
  public_network_access_enabled = false
  local_authentication_disabled = true
  free_tier_enabled             = false
  enable_telemetry              = var.enable_telemetry
  tags                          = local.default_tags

  consistency_policy = {
    consistency_level = "Session"
  }

  geo_locations = [
    {
      location          = var.location
      failover_priority = 0
      zone_redundant    = false
    }
  ]

  private_endpoints = {
    sql = {
      name                          = "pep-cosmos-${local.name_prefix}"
      subnet_resource_id            = module.vnet.subnets["snet-pe"].resource_id
      subresource_name              = "Sql"
      private_dns_zone_resource_ids = [module.dns_cosmos.resource_id]
    }
  }
}

# AVM v0.10.0 bug workaround: the cosmos module at .terraform/modules/cosmos/main.tf:15
# forces local_authentication_disabled = false when no sql_databases are
# declared in the module input, regardless of what we pass. Foundry creates
# its databases at runtime, not via TF, so we never declare sql_databases —
# meaning the module silently re-enables local auth. This azapi_update_resource
# enforces the actual intent (AAD-only) after the module finishes.
#
# Fix is upstream on main (commit 3c6139c, PR #136, merged 2026-03-20) but
# not yet in a tagged release. Remove this workaround when v0.10.1+ ships.
# Tracking: https://github.com/Azure/terraform-azurerm-avm-res-documentdb-databaseaccount/issues/124
resource "azapi_update_resource" "cosmos_disable_local_auth" {
  type        = "Microsoft.DocumentDB/databaseAccounts@2024-05-15"
  resource_id = module.cosmos.resource_id

  body = {
    properties = {
      disableLocalAuth = true
    }
  }

  depends_on = [module.cosmos]
}
