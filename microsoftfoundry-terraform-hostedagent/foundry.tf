# ==============================================================================
# Cognitive Services Account Lifecycle Helpers
# ==============================================================================
# These run on destroy to clean up the soft-deleted account and to wait for
# the Microsoft-managed networkInjection cleanup before the agent subnet can
# be removed. Documented inline; do not reorder dependencies casually.
# ==============================================================================

# Purge the Cognitive Services account after Terraform soft-deletes it.
# By default, Azure soft-deletes Cognitive Services accounts. The managed
# Container Apps Environment (legionservicelink) on the agent subnet is
# not fully cleaned up until the account is purged.
# See: https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/virtual-networks#template-deployment-errors
resource "terraform_data" "purge_ai_account" {
  # Create-order: this resource is created BEFORE ai_account (see ai_account's
  # depends_on below). Terraform reverses dependencies on destroy, so the
  # provisioner here runs AFTER ai_account is destroyed — exactly when the
  # account exists in soft-deleted state and can be purged.
  depends_on = [terraform_data.wait_for_network_injection_cleanup]

  input = {
    account_name = local.account_name
    location     = azurerm_resource_group.this.location
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Purging soft-deleted Cognitive Services account '${self.input.account_name}' in '${self.input.location}'..."
      az cognitiveservices account purge \
        --name '${self.input.account_name}' \
        --location '${self.input.location}' \
        2>&1 || echo "Purge returned non-zero (account may already be purged or not yet soft-deleted). Continuing."
      echo "Purge command completed."
    EOT
  }
}

# Guard the agent subnet against premature deletion.
# On destroy, Terraform reverses the dependency chain:
#   ai_account destroyed → purge provisioner runs → polling provisioner waits → vnet can be destroyed
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

# The MCP subnet is also delegated to Microsoft.App/environments (private MCP
# Container Apps Environment), so it gets its own service association link that
# releases asynchronously after the CAE is torn down. Poll it too, otherwise a
# fast VNet/subnet teardown can still hit SubnetIsInUseByAnotherResource.
resource "terraform_data" "wait_for_mcp_subnet_cleanup" {
  depends_on = [module.vnet]

  input = {
    resource_group_name = azurerm_resource_group.this.name
    vnet_name           = module.vnet.resource.name
    subnet_name         = "snet-mcp-${local.name_prefix}-${var.instance}"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${path.module}/wait-for-subnet-cleanup.sh '${self.input.resource_group_name}' '${self.input.vnet_name}' '${self.input.subnet_name}' 30 900"
  }
}

# ==============================================================================
# AI Services Account (Microsoft.CognitiveServices/accounts)
# ==============================================================================

resource "azapi_resource" "ai_account" {
  type      = "Microsoft.CognitiveServices/accounts@2025-06-01"
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
      disableLocalAuth       = true
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

  timeouts {
    create = "90m"
    delete = "60m"
  }

  depends_on = [terraform_data.purge_ai_account]
}

# ==============================================================================
# Model Deployment (e.g. gpt-4o-mini)
# ==============================================================================

resource "azapi_resource" "model_deployment" {
  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-06-01"
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
# AI Foundry Project
# ==============================================================================

resource "azapi_resource" "ai_project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
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
# Account-level Foundry Connections (KV first, then AppInsights)
# ==============================================================================

# Bring-Your-Own Key Vault connection.
# MUST be the first connection on the Foundry account — the service blocks KV
# connection creation if other connections already exist. The `depends_on`
# chain on every other Foundry connection (below) enforces this ordering on
# any greenfield apply.
#
# API stays on @2025-04-01-preview because category=AzureKeyVault and
# authType=AccountManagedIdentity are absent from the GA schema (same reason
# capability_host below stays on preview).
#
# Ref: https://learn.microsoft.com/en-us/azure/foundry/how-to/set-up-key-vault-connection
resource "azapi_resource" "conn_keyvault" {
  type      = "Microsoft.CognitiveServices/accounts/connections@2025-04-01-preview"
  name      = "${local.account_name}-keyvault"
  parent_id = azapi_resource.ai_account.id

  schema_validation_enabled = false

  body = {
    properties = {
      category      = "AzureKeyVault"
      authType      = "AccountManagedIdentity"
      target        = module.keyvault.resource_id
      isSharedToAll = true
      metadata = {
        ApiType    = "Azure"
        ResourceId = module.keyvault.resource_id
        location   = azurerm_resource_group.this.location
      }
    }
  }

  # Wait for the Foundry SAMI Secrets Officer role to propagate (the Azure
  # control plane validates Foundry can access the KV when creating the
  # connection). The time_sleep is sized for typical RBAC propagation.
  depends_on = [time_sleep.wait_for_kv_rbac]
}

# Account-level Application Insights connection.
# Foundry stores the conn string as an auto-named secret in BYO KV (single
# source of truth — no separate azurerm_key_vault_secret needed). App code
# retrieves the value via
# `AIProjectClient.telemetry.get_application_insights_connection_string()`,
# which requires the caller MI to hold the Foundry User role on the project.
resource "azapi_resource" "conn_appinsights" {
  type      = "Microsoft.CognitiveServices/accounts/connections@2025-06-01"
  name      = "appinsights-conn"
  parent_id = azapi_resource.ai_account.id

  schema_validation_enabled = false

  body = {
    properties = {
      category      = "AppInsights"
      authType      = "ApiKey"
      target        = azurerm_application_insights.this.id
      isSharedToAll = true
      credentials = {
        key = azurerm_application_insights.this.connection_string
      }
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_application_insights.this.id
      }
    }
  }

  depends_on = [azapi_resource.conn_keyvault]
}

# ==============================================================================
# Project-level Connections (Cosmos DB, Storage, AI Search)
# ==============================================================================
# All three depend on conn_keyvault to enforce the "KV connection must be
# first on the Foundry account" rule on any greenfield apply.
# Ref: https://learn.microsoft.com/en-us/azure/foundry/how-to/set-up-key-vault-connection
# ==============================================================================

resource "azapi_resource" "connection_cosmosdb" {
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name      = local.cosmos_db_name
  parent_id = azapi_resource.ai_project.id

  depends_on = [azapi_resource.conn_keyvault]

  body = {
    properties = {
      category = "CosmosDb"
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
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name      = local.storage_name
  parent_id = azapi_resource.ai_project.id

  depends_on = [azapi_resource.conn_keyvault]

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
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-06-01"
  name      = local.ai_search_name
  parent_id = azapi_resource.ai_project.id

  depends_on = [azapi_resource.conn_keyvault]

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
# Capability Host — Project-level (Agents)
#
# Account-level capability host is NOT declared here: when
# networkInjections.scenario = "agent" is set on the AI account, Azure
# auto-provisions an account-level capability host with private networking
# (enablePublicHostingEnvironment = false, customerSubnet = snet-agent).
# Creating a second one would conflict (409).
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

  timeouts {
    create = "60m"
    delete = "60m"
  }

  depends_on = [
    azapi_resource.connection_cosmosdb,
    azapi_resource.connection_storage,
    azapi_resource.connection_search,
    azurerm_role_assignment.cosmos_operator,
    azurerm_role_assignment.storage_blob_contributor,
    azurerm_role_assignment.search_index_data_contributor,
    azurerm_role_assignment.search_service_contributor,
    azurerm_role_assignment.foundry_user,
  ]
}
