# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------
data "azurerm_client_config" "current" {}

data "azuread_service_principal" "aro_rp" {
  client_id = var.aro_rp_client_id
}

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
# Subnets: Master, Worker, Private Endpoint, WireGuard
# Master/Worker subnets require service endpoints for ARO
# -----------------------------------------------------------------------------
module "vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.17.1"

  location  = azurerm_resource_group.this.location
  name      = local.resource_names.vnet
  parent_id = azurerm_resource_group.this.id

  address_space = var.vnet_address_space

  subnets = {
    master = {
      name                                          = local.subnets.master.name
      address_prefixes                              = local.subnets.master.address_prefixes
      default_outbound_access_enabled                = false
      private_link_service_network_policies_enabled = false
      service_endpoints                             = ["Microsoft.Storage", "Microsoft.ContainerRegistry"]
      nat_gateway = {
        id = module.nat_gateway.resource_id
      }
    }
    worker = {
      name                                          = local.subnets.worker.name
      address_prefixes                              = local.subnets.worker.address_prefixes
      default_outbound_access_enabled                = false
      private_link_service_network_policies_enabled = false
      service_endpoints                             = ["Microsoft.Storage", "Microsoft.ContainerRegistry"]
      nat_gateway = {
        id = module.nat_gateway.resource_id
      }
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
