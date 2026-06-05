locals {
  name_prefix = "${var.workload}-${var.environment}"

  default_tags = merge(var.tags, {
    environment = var.environment
    managed_by  = "terraform"
    workload    = var.workload
  })
}
