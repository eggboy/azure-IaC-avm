# Azure Machine Learning Workspace with Managed VNet
module "ml_workspace" {
  source  = "Azure/avm-res-machinelearningservices-workspace/azurerm"
  version = "0.9.0"

  enable_telemetry    = var.enable_telemetry
  kind                = "Default"
  location            = azurerm_resource_group.this.location
  name                = "mlw-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.default_tags

  # Associated services
  application_insights = {
    resource_id = module.app_insights.resource_id
  }
  container_registry = {
    resource_id = module.container_registry.resource_id
  }
  key_vault = {
    resource_id = module.key_vault.resource_id
  }
  storage_account = {
    resource_id = module.storage_account.resource_id
  }

  # Disable public internet access
  public_network_access_enabled = false

  # Managed identities
  managed_identities = {
    system_assigned            = true
    user_assigned_resource_ids = [module.identity.resource_id]
  }

  # Private endpoint for ML workspace
  private_endpoints = {
    ml_workspace = {
      name                          = "pep-mlw-${local.name_prefix}"
      subnet_resource_id            = module.vnet.subnets["snet-pe"].resource_id
      private_dns_zone_resource_ids = [azurerm_private_dns_zone.ml_api.id, azurerm_private_dns_zone.ml_notebooks.id]
    }
  }

  # Serverless compute — managed VNet handles networking; no custom subnet needed
  serverless_compute = {
    public_ip_enabled = false
  }

  # Use a dedicated compute cluster to build Docker images when ACR is behind a private endpoint
  image_build_compute = "image-builder"

  # Managed VNet configuration
  workspace_managed_network = {
    isolation_mode = "AllowInternetOutbound"
    spark_ready    = true
  }

  depends_on = [azurerm_resource_group.this]
}

# CPU compute cluster for Docker image builds (required when ACR has no public access)
# Uses azapi_resource because azurerm_machine_learning_compute_cluster does not support
# Managed VNet workspaces — it always tries to place compute in a custom VNet subnet.
resource "azapi_resource" "image_builder" {
  type      = "Microsoft.MachineLearningServices/workspaces/computes@2024-10-01"
  name      = "image-builder"
  parent_id = module.ml_workspace.resource_id
  location  = azurerm_resource_group.this.location
  tags      = local.default_tags

  identity {
    type         = "UserAssigned"
    identity_ids = [module.identity.resource_id]
  }

  body = {
    properties = {
      computeType = "AmlCompute"
      properties = {
        vmSize                      = "Standard_DS3_v2"
        vmPriority                  = "LowPriority"
        enableNodePublicIp          = false
        osType                      = "Linux"
        remoteLoginPortPublicAccess = "Disabled"
        scaleSettings = {
          minNodeCount                = 0
          maxNodeCount                = 2
          nodeIdleTimeBeforeScaleDown = "PT120S"
        }
      }
    }
  }
}
