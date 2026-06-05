# ==============================================================================
# API Management v2 (PremiumV2) — VNet Injected
# Gated by var.enable_apim. When disabled, no APIM-related resources are
# created (also see nsg_apim, dns_apim, and snet-apim in main.tf).
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
