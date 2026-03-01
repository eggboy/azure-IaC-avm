# User Assigned Managed Identity for Azure ML Workspace
module "identity" {
  source  = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version = "0.3.4"

  enable_telemetry    = var.enable_telemetry
  location            = azurerm_resource_group.this.location
  name                = "id-${local.name_prefix}-${var.instance}"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.default_tags
}
