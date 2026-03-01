locals {
  # Azure naming convention: <abbreviation>-<project>-<environment>-<region>
  default_tags = merge(var.tags, {
    environment = var.environment
    managed_by  = "terraform"
    project     = var.project
  })

  name_prefix = "${var.project}-${var.environment}-${var.location}"
}
