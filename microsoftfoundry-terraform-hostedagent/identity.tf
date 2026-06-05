# ==============================================================================
# Role Assignments — AI Project System-Assigned Identity
# ==============================================================================

# ----- Foundry User Role -----

# Foundry User — grants the project managed identity data-plane access to the
# Foundry resource. Without it, agents and other Foundry features will fail.
# GUID is held in local.role_definition_ids.foundry_user to avoid breakage
# during the Foundry role rename rollout.
# See: https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry
resource "azurerm_role_assignment" "foundry_user" {
  scope                            = azapi_resource.ai_account.id
  role_definition_id               = "${local.role_definition_id_prefix}/${local.role_definition_ids.foundry_user}"
  principal_id                     = local.project_principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# ----- AI Search Roles -----

# Search Index Data Contributor (8ebe5a00-799e-43f5-93ac-243d3dce84a7)
resource "azurerm_role_assignment" "search_index_data_contributor" {
  scope                            = module.search.resource_id
  role_definition_name             = "Search Index Data Contributor"
  principal_id                     = local.project_principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# Search Service Contributor (7ca78c08-252a-4471-8644-bb5ff32d4ba0)
resource "azurerm_role_assignment" "search_service_contributor" {
  scope                            = module.search.resource_id
  role_definition_name             = "Search Service Contributor"
  principal_id                     = local.project_principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# ----- Cosmos DB Roles -----

# Cosmos DB Operator (230815da-be43-4aae-9cb4-875f7bd000aa)
resource "azurerm_role_assignment" "cosmos_operator" {
  scope                            = module.cosmos.resource_id
  role_definition_name             = "Cosmos DB Operator"
  principal_id                     = local.project_principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# Cosmos DB Built-In Data Contributor (SQL role assignment — must be created after capability host)
resource "azurerm_cosmosdb_sql_role_assignment" "data_contributor" {
  resource_group_name = azurerm_resource_group.this.name
  account_name        = module.cosmos.name
  # Built-in Cosmos DB Data Contributor role definition
  role_definition_id = "${module.cosmos.resource_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id       = local.project_principal_id
  scope              = module.cosmos.resource_id

  depends_on = [azapi_resource.capability_host]
}

# Cosmos DB Built-In Data Contributor scoped to enterprise_memory database
resource "azurerm_cosmosdb_sql_role_assignment" "enterprise_memory_db" {
  name                = uuidv5("dns", "${azapi_resource.ai_project.name}${local.project_principal_id}enterprise_memory_db_sql_role")
  resource_group_name = azurerm_resource_group.this.name
  account_name        = module.cosmos.name
  role_definition_id  = "${module.cosmos.resource_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = local.project_principal_id
  scope               = "${module.cosmos.resource_id}/dbs/enterprise_memory"

  depends_on = [azapi_resource.capability_host]
}

# ----- Storage Roles -----

# Storage Blob Data Contributor (ba92f5b4-2d11-453d-a403-e96b0029c9fe)
resource "azurerm_role_assignment" "storage_blob_contributor" {
  scope                            = module.storage.resource_id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = local.project_principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# Storage Blob Data Owner with RBAC condition (must be after capability host)
resource "azurerm_role_assignment" "storage_blob_owner" {
  scope                            = module.storage.resource_id
  role_definition_name             = "Storage Blob Data Owner"
  principal_id                     = local.project_principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
  condition_version                = "2.0"
  condition                        = "((!(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/read'})  AND  !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/filter/action'}) AND  !(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/write'}) ) OR (@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringStartsWithIgnoreCase '${local.project_workspace_id}' AND @Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringLikeIgnoreCase '*-azureml-agent'))"

  depends_on = [azapi_resource.capability_host]
}

# ----- Container Registry Roles (for Hosted Agents) -----

# AcrPull — allows the project managed identity to pull container images
# from ACR for hosted agent deployments.
resource "azurerm_role_assignment" "acr_pull" {
  scope                            = module.acr.resource_id
  role_definition_name             = "AcrPull"
  principal_id                     = local.project_principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# ----- Key Vault Roles -----

# Key Vault Secrets Officer granted to the Terraform runner. Lets the apply
# write/manage secrets in the KV later (e.g., bootstrap third-party API
# tokens, custom connection credentials). Currently unused by Phase D — the
# AppInsights conn string is owned by Foundry in BYO KV — but kept so future
# ad-hoc secrets don't require a separate apply. GUID is held in
# local.role_definition_ids.key_vault_secrets_officer per AVM convention.
resource "azurerm_role_assignment" "kv_secrets_officer_caller" {
  scope              = module.keyvault.resource_id
  role_definition_id = "${local.role_definition_id_prefix}/${local.role_definition_ids.key_vault_secrets_officer}"
  principal_id       = data.azurerm_client_config.current.object_id
}

# Key Vault Secrets Officer granted to the Foundry account's system-assigned
# managed identity. Required so Foundry's runtime can create, read, and
# rotate the secrets it stores in BYO KV for non-Entra connections (e.g.,
# the AppInsights ApiKey credential). Matches MS's set-up-key-vault-connection
# Bicep sample.
# Ref: https://learn.microsoft.com/en-us/azure/foundry/how-to/set-up-key-vault-connection
resource "azurerm_role_assignment" "kv_secrets_officer_foundry" {
  scope                            = module.keyvault.resource_id
  role_definition_id               = "${local.role_definition_id_prefix}/${local.role_definition_ids.key_vault_secrets_officer}"
  principal_id                     = azapi_resource.ai_account.output.identity.principalId
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# Wait for the Foundry SAMI Secrets Officer role assignment to propagate
# before the conn_keyvault create call validates Foundry can access the KV.
# Mirrors the existing wait_for_ai_account pattern in private_endpoints.tf.
resource "time_sleep" "wait_for_kv_rbac" {
  depends_on      = [azurerm_role_assignment.kv_secrets_officer_foundry]
  create_duration = "60s"
}
