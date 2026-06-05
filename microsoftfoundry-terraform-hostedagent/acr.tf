# ==============================================================================
# Azure Container Registry (for Hosted Agent container images)
# ==============================================================================

module "acr" {
  source  = "Azure/avm-res-containerregistry-registry/azurerm"
  version = "0.5.1"

  name                          = local.acr_name
  resource_group_name           = azurerm_resource_group.this.name
  location                      = azurerm_resource_group.this.location
  sku                           = "Premium"
  public_network_access_enabled = false
  admin_enabled                 = false
  enable_telemetry              = var.enable_telemetry
  tags                          = local.default_tags

  private_endpoints = {
    registry = {
      name                          = "pep-cr-${local.name_prefix}"
      subnet_resource_id            = module.vnet.subnets["snet-pe"].resource_id
      private_dns_zone_resource_ids = [module.dns_acr.resource_id]
    }
  }
}
