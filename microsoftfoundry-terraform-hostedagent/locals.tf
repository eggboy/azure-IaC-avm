locals {
  account_name            = lower("ais-${var.workload}-${var.environment}-${local.unique_suffix}")
  acr_name                = lower("cr${var.workload}${var.environment}${local.unique_suffix}")
  ai_search_name          = lower("srch-${var.workload}-${var.environment}-${local.unique_suffix}")
  apim_name               = "apim-${var.workload}-${var.environment}-${local.unique_suffix}"
  app_insights_name       = "appi-${var.workload}-${var.environment}-${local.unique_suffix}"
  container_apps_env_name = "cae-${var.workload}-${var.environment}-${local.unique_suffix}"
  cosmos_db_name          = lower("cosmos-${var.workload}-${var.environment}-${local.unique_suffix}")
  # KV name has a hard 24-character limit. substr(workload, 0, 12) keeps the
  # name compliant even when var.workload is longer than the default.
  # Layout: kv-(3) + workload(<=12) + -(1) + env(3) + -(1) + suffix(4) = 24
  key_vault_name     = lower("kv-${substr(var.workload, 0, 12)}-${var.environment}-${local.unique_suffix}")
  log_analytics_name = "log-${var.workload}-${var.environment}-${local.unique_suffix}"

  default_tags = merge(var.tags, {
    environment = var.environment
    managed_by  = "terraform"
    workload    = var.workload
  })

  name_prefix    = "${var.workload}-${var.environment}-${var.location}"
  no_zrs_regions = ["southindia", "westus"]
  project_name   = lower("proj-${var.first_project_name}-${local.unique_suffix}")
  storage_name   = lower("st${var.workload}${var.environment}${local.unique_suffix}")
  storage_sku    = contains(local.no_zrs_regions, var.location) ? "Standard_GRS" : "Standard_ZRS"
  unique_suffix  = random_string.suffix.result

  # Project system-assigned identity values extracted from the azapi response.
  # Kept here (rather than alongside the consumer in identity.tf) per the
  # locals.tf convention.
  project_principal_id = azapi_resource.ai_project.output.identity.principalId
  # internalId format: /subscriptions/.../workspaces/<guid> — we need the last segment
  project_workspace_id = element(split("/", azapi_resource.ai_project.output.properties.internalId),
    length(split("/", azapi_resource.ai_project.output.properties.internalId)) - 1
  )

  # Built-in role-definition GUIDs we reference by GUID (rather than by name)
  # to avoid breakage during Microsoft's Foundry role rename rollouts and to
  # follow AVM convention.
  # Ref: https://learn.microsoft.com/en-us/azure/foundry/concepts/rbac-foundry
  role_definition_id_prefix = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions"
  role_definition_ids = {
    foundry_user              = "53ca6127-db72-4b80-b1b0-d745d6d5456d"
    key_vault_secrets_officer = "b86a8fe4-44ce-4948-aee5-eccb2c155cd7"
  }
}
