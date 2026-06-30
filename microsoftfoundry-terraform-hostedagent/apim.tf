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

# Purge the soft-deleted APIM instance on destroy. APIM soft-deletes by default;
# the soft-deleted record keeps the service name reserved, so a redeploy with the
# same name fails until it's purged. Mirrors purge_ai_account in foundry.tf.
resource "terraform_data" "purge_apim" {
  count = var.enable_apim ? 1 : 0

  input = {
    apim_name = local.apim_name
    location  = azurerm_resource_group.this.location
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Purging soft-deleted API Management '${self.input.apim_name}' in '${self.input.location}'..."
      az apim deletedservice purge --service-name '${self.input.apim_name}' --location '${self.input.location}' \
        2>&1 || echo "Purge returned non-zero (APIM may already be purged or not yet soft-deleted). Continuing."
      echo "APIM purge command completed."
    EOT
  }

  depends_on = [module.apim]
}
