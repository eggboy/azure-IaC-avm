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
# Container Apps Environment — Internal-only (MCP Subnet, AVM Module)
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

# ==============================================================================
# AI Services Account (Microsoft.CognitiveServices/accounts)
# ==============================================================================

# Guard the agent subnet against premature deletion.
# On destroy, Terraform reverses the dependency chain:
#   ai_account destroyed → polling provisioner waits → vnet can be destroyed
# The networkInjections feature creates a managed Container Apps Environment
# (legionservicelink) in a Microsoft-managed subscription (hobov3_*).
# Its async cleanup can take 10+ minutes — a fixed sleep is unreliable,
# so we poll the subnet until the service association link is gone.
resource "terraform_data" "wait_for_network_injection_cleanup" {
  depends_on = [module.vnet]

  input = {
    resource_group_name = azurerm_resource_group.this.name
    vnet_name           = module.vnet.resource.name
    subnet_name         = "snet-agent-${local.name_prefix}-${var.instance}"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/wait-for-subnet-cleanup.sh '${self.input.resource_group_name}' '${self.input.vnet_name}' '${self.input.subnet_name}' 30 900"
  }
}

resource "azapi_resource" "ai_account" {
  type      = "Microsoft.CognitiveServices/accounts@2025-04-01-preview"
  name      = local.account_name
  location  = azurerm_resource_group.this.location
  parent_id = azurerm_resource_group.this.id

  identity {
    type = "SystemAssigned"
  }

  body = {
    kind = "AIServices"
    sku = {
      name = "S0"
    }
    properties = {
      allowProjectManagement = true
      customSubDomainName    = local.account_name
      publicNetworkAccess    = "Disabled"
      disableLocalAuth       = false
      networkAcls = {
        defaultAction       = "Deny"
        virtualNetworkRules = []
        ipRules             = []
        bypass              = "AzureServices"
      }
      networkInjections = [
        {
          scenario                   = "agent"
          subnetArmId                = module.vnet.subnets["snet-agent"].resource_id
          useMicrosoftManagedNetwork = false
        }
      ]
    }
  }

  tags = local.default_tags

  response_export_values = [
    "properties.endpoint",
    "identity.principalId"
  ]

  depends_on = [terraform_data.wait_for_network_injection_cleanup]
}

# ==============================================================================
# Model Deployment (e.g. gpt-4o-mini)
# ==============================================================================

resource "azapi_resource" "model_deployment" {
  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview"
  name      = var.model_name
  parent_id = azapi_resource.ai_account.id

  body = {
    sku = {
      capacity = var.model_capacity
      name     = var.model_sku_name
    }
    properties = {
      model = {
        name    = var.model_name
        format  = var.model_format
        version = var.model_version
      }
    }
  }
}

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

# ==============================================================================
# AI Foundry Project
# ==============================================================================

resource "azapi_resource" "ai_project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview"
  name      = local.project_name
  location  = azurerm_resource_group.this.location
  parent_id = azapi_resource.ai_account.id

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      description = var.project_description
      displayName = var.project_display_name
    }
  }

  tags = local.default_tags

  response_export_values = [
    "identity.principalId",
    "properties.internalId"
  ]

  depends_on = [
    azurerm_private_endpoint.ai_account,
    module.storage,
    module.search,
    module.cosmos,
  ]
}

# ==============================================================================
# Project Connections (Cosmos DB, Storage, AI Search)
# ==============================================================================

resource "azapi_resource" "connection_cosmosdb" {
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = local.cosmos_db_name
  parent_id = azapi_resource.ai_project.id

  body = {
    properties = {
      category = "CosmosDB"
      target   = module.cosmos.endpoint
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = module.cosmos.resource_id
        location   = azurerm_resource_group.this.location
      }
    }
  }
}

resource "azapi_resource" "connection_storage" {
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = local.storage_name
  parent_id = azapi_resource.ai_project.id

  body = {
    properties = {
      category = "AzureStorageAccount"
      target   = module.storage.resource.primary_blob_endpoint
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = module.storage.resource_id
        location   = azurerm_resource_group.this.location
      }
    }
  }
}

resource "azapi_resource" "connection_search" {
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = local.ai_search_name
  parent_id = azapi_resource.ai_project.id

  body = {
    properties = {
      category = "CognitiveSearch"
      target   = "https://${module.search.resource.name}.search.windows.net"
      authType = "AAD"
      metadata = {
        ApiType    = "Azure"
        ResourceId = module.search.resource_id
        location   = azurerm_resource_group.this.location
      }
    }
  }
}

# ==============================================================================
# Capability Host (Agents)
# ==============================================================================

resource "azapi_resource" "capability_host" {
  type      = "Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview"
  name      = "caphostproj"
  parent_id = azapi_resource.ai_project.id

  schema_validation_enabled = false

  body = {
    properties = {
      capabilityHostKind       = "Agents"
      vectorStoreConnections   = [local.ai_search_name]
      storageConnections       = [local.storage_name]
      threadStorageConnections = [local.cosmos_db_name]
    }
  }

  depends_on = [
    azapi_resource.connection_cosmosdb,
    azapi_resource.connection_storage,
    azapi_resource.connection_search,
    azurerm_role_assignment.cosmos_operator,
    azurerm_role_assignment.storage_blob_contributor,
    azurerm_role_assignment.search_index_data_contributor,
    azurerm_role_assignment.search_service_contributor,
  ]
}

# ==============================================================================
# API Management v2 (PremiumV2) — VNet Injected
# ==============================================================================

module "apim" {
  source  = "Azure/avm-res-apimanagement-service/azurerm"
  version = "0.0.7"
  count   = var.enable_apim ? 1 : 0

  enable_telemetry              = var.enable_telemetry
  location                      = azurerm_resource_group.this.location
  name                          = local.apim_name
  publisher_email               = var.apim_publisher_email
  publisher_name                = var.apim_publisher_name
  resource_group_name           = azurerm_resource_group.this.name
  sku_name                      = "PremiumV2_${var.apim_sku_capacity}"
  public_network_access_enabled = false
  virtual_network_type          = "Internal"
  virtual_network_subnet_id     = module.vnet.subnets["snet-apim"].resource_id
  tags                          = local.default_tags
}


