# ==============================================================================
# Role Assignments — AI Project System-Assigned Identity
# ==============================================================================

locals {
  # Extract the project principal ID from azapi response
  project_principal_id = azapi_resource.ai_project.output.identity.principalId

  # Extract project workspace GUID from internalId
  # internalId format: /subscriptions/.../workspaces/<guid>  — we need the last segment
  project_workspace_id = element(split("/", azapi_resource.ai_project.output.properties.internalId),
    length(split("/", azapi_resource.ai_project.output.properties.internalId)) - 1
  )
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
