locals {
  name_prefix = "${var.workload}-${var.environment}"

  # Azure CAF naming convention: <abbreviation>-<workload>-<environment>-<region>-<instance>
  resource_names = {
    aks                  = "aks-${local.name_prefix}-${var.location}-001"
    aks_identity         = "id-aks-${local.name_prefix}-${var.location}-001"
    container_registry   = "cr${var.workload}${var.environment}${var.location}001"
    firewall             = "afw-${local.name_prefix}-${var.location}-001"
    firewall_policy      = "afwp-${local.name_prefix}-${var.location}-001"
    log_analytics        = "log-${local.name_prefix}-${var.location}-001"
    nsg_wireguard        = "nsg-wg-${local.name_prefix}-${var.location}-001"
    public_ip_firewall   = "pip-afw-${local.name_prefix}-${var.location}-001"
    resource_group       = "rg-${local.name_prefix}-${var.location}-001"
    route_table_firewall = "rt-afw-${local.name_prefix}-${var.location}-001"
    vnet                 = "vnet-${local.name_prefix}-${var.location}-001"
  }

  # Subnet definitions matching the sg-aks-workshop architecture
  subnets = {
    aks = {
      address_prefixes = ["100.64.1.0/24"]
      name             = "snet-aks-${local.name_prefix}-${var.location}-001"
    }
    appgw = {
      address_prefixes = ["100.64.3.0/26"]
      name             = "snet-agw-${local.name_prefix}-${var.location}-001"
    }
    firewall = {
      address_prefixes = ["100.64.4.0/26"]
      name             = "AzureFirewallSubnet" # Required name for Azure Firewall
    }
    ilb = {
      address_prefixes = ["100.64.2.0/24"]
      name             = "snet-ilb-${local.name_prefix}-${var.location}-001"
    }
    pe = {
      address_prefixes = ["100.64.6.0/26"]
      name             = "snet-pe-${local.name_prefix}-${var.location}-001"
    }
    wireguard = {
      address_prefixes = ["100.64.5.0/26"]
      name             = "snet-wg-${local.name_prefix}-${var.location}-001"
    }
  }

  tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Workload    = var.workload
  })
}
