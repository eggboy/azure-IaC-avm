# ==============================================================================
# Key Vault (AVM Module)
# Used for two purposes:
#   1. Foundry "Bring Your Own KV" — once wired via azapi_resource.conn_keyvault
#      (Phase D), Foundry stores credentials of any non-Entra connection
#      (ApiKey, AccessKey, OAuth2, etc.) in THIS vault instead of in the
#      Microsoft-managed KV outside the subscription.
#      Ref: https://learn.microsoft.com/en-us/azure/foundry/how-to/set-up-key-vault-connection
#   2. App-layer secret storage for future container apps / MCP / hosted agent
#      tool code that reads secrets via DefaultAzureCredential + SecretClient.
#
# Name format kv-<workload[0:12]>-<env>-<4-char-suffix> fits the 24-char limit
# (see locals.tf for the substr truncation rationale).
# ==============================================================================

module "keyvault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.10.2"

  name                = local.key_vault_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  enable_telemetry    = var.enable_telemetry
  tags                = local.default_tags

  sku_name                      = "standard"
  purge_protection_enabled      = true
  soft_delete_retention_days    = 7
  public_network_access_enabled = false

  network_acls = {
    bypass         = "AzureServices"
    default_action = "Deny"
  }

  private_endpoints = {
    vault = {
      name                          = "pep-kv-${local.name_prefix}"
      subnet_resource_id            = module.vnet.subnets["snet-pe"].resource_id
      private_dns_zone_resource_ids = [module.dns_keyvault.resource_id]
    }
  }
}
