# -----------------------------------------------------------------------------
# NAT Gateway (AVM)
# Provides a static outbound public IP for ARO master and worker subnets.
# All egress traffic from the cluster uses this NAT Gateway instead of
# Azure default outbound access or a load balancer SNAT.
# Reference: https://learn.microsoft.com/en-us/azure/nat-gateway/nat-overview
# -----------------------------------------------------------------------------
module "nat_gateway" {
  source  = "Azure/avm-res-network-natgateway/azurerm"
  version = "0.3.2"

  location  = azurerm_resource_group.this.location
  name      = local.resource_names.nat_gateway
  parent_id = azurerm_resource_group.this.id

  idle_timeout_in_minutes = 10

  # Create a dedicated public IP for NAT Gateway egress
  public_ips = {
    pip_1 = {
      name = "pip-ng-${local.name_prefix}-${var.location}-001"
    }
  }

  tags = local.tags
}
