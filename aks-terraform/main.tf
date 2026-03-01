# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------
resource "azurerm_resource_group" "this" {
  location = var.location
  name     = local.resource_names.resource_group
  tags     = local.tags
}

# -----------------------------------------------------------------------------
# Virtual Network with Subnets (AVM)
# Subnets: AKS, ILB, App Gateway, Azure Firewall
# Reference: https://github.com/eggboy/sg-aks-workshop/tree/master/cluster-pre-provisioning
# -----------------------------------------------------------------------------
module "vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.17.1"

  location  = azurerm_resource_group.this.location
  name      = local.resource_names.vnet
  parent_id = azurerm_resource_group.this.id

  address_space = var.vnet_address_space

  subnets = {
    aks = {
      name                            = local.subnets.aks.name
      address_prefixes                = local.subnets.aks.address_prefixes
      default_outbound_access_enabled = false
    }
    appgw = {
      name             = local.subnets.appgw.name
      address_prefixes = local.subnets.appgw.address_prefixes
    }
    firewall = {
      name             = local.subnets.firewall.name
      address_prefixes = local.subnets.firewall.address_prefixes
    }
    ilb = {
      name                            = local.subnets.ilb.name
      address_prefixes                = local.subnets.ilb.address_prefixes
      default_outbound_access_enabled = false
    }
    pe = {
      name                              = local.subnets.pe.name
      address_prefixes                  = local.subnets.pe.address_prefixes
      private_endpoint_network_policies = "Disabled"
    }
    wireguard = {
      name             = local.subnets.wireguard.name
      address_prefixes = local.subnets.wireguard.address_prefixes
      network_security_group = {
        id = module.nsg_wireguard.resource_id
      }
    }
  }

  tags = local.tags
}
