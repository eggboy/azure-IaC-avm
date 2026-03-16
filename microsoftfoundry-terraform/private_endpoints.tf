# ==============================================================================
# Private Endpoints
# ==============================================================================

# Wait for AI account network injection sub-operation to complete
# The azapi LRO finishes before provisioningState leaves "Accepted"
resource "time_sleep" "wait_for_ai_account" {
  depends_on      = [azapi_resource.ai_account]
  create_duration = "120s"
}

# AI Services Account private endpoint (group: account)
# Kept as raw resource because azapi_resource.ai_account is a preview API resource
resource "azurerm_private_endpoint" "ai_account" {
  name                = "pep-ais-${local.name_prefix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = module.vnet.subnets["snet-pe"].resource_id
  tags                = local.default_tags

  depends_on = [time_sleep.wait_for_ai_account]

  private_service_connection {
    name                           = "psc-ais-${local.name_prefix}"
    private_connection_resource_id = azapi_resource.ai_account.id
    is_manual_connection           = false
    subresource_names              = ["account"]
  }

  private_dns_zone_group {
    name = "dzg-ais-${local.name_prefix}"
    private_dns_zone_ids = [
      module.dns_ai_services.resource_id,
      module.dns_openai.resource_id,
      module.dns_cognitive_services.resource_id,
    ]
  }
}
