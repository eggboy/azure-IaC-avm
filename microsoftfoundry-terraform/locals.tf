locals {
  account_name            = lower("ais-${var.workload}-${var.environment}-${local.unique_suffix}")
  ai_search_name          = lower("srch-${var.workload}-${var.environment}-${local.unique_suffix}")
  apim_name               = "apim-${var.workload}-${var.environment}-${local.unique_suffix}"
  container_apps_env_name = "cae-${var.workload}-${var.environment}-${local.unique_suffix}"
  cosmos_db_name          = lower("cosmos-${var.workload}-${var.environment}-${local.unique_suffix}")
  log_analytics_name      = "log-${var.workload}-${var.environment}-${local.unique_suffix}"

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
  unique_suffix  = substr(random_string.suffix.result, 0, 4)
}
