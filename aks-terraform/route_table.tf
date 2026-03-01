# -----------------------------------------------------------------------------
# Route Table for Azure Firewall (AVM)
# Forces AKS egress traffic through the Azure Firewall
# -----------------------------------------------------------------------------
module "route_table_firewall" {
  source  = "Azure/avm-res-network-routetable/azurerm"
  version = "0.5.0"

  location            = azurerm_resource_group.this.location
  name                = local.resource_names.route_table_firewall
  resource_group_name = azurerm_resource_group.this.name

  bgp_route_propagation_enabled = false

  routes = {
    default_to_firewall = {
      name                   = "default-to-firewall"
      address_prefix         = "0.0.0.0/0"
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = module.firewall.resource.ip_configuration[0].private_ip_address
    }
  }

  # Associate route table with AKS subnet to force egress through the firewall
  subnet_resource_ids = {
    aks = module.vnet.subnets["aks"].resource_id
  }

  tags = local.tags
}
