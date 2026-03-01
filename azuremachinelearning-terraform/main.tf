# State migration: nsg_jumphost → nsg_wireguard (rename only, no infra change)
moved {
  from = module.nsg_jumphost
  to   = module.nsg_wireguard
}

# Resource Group
resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.default_tags
}



# Network Security Group - ML Subnet
module "nsg_ml" {
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "0.5.1"

  enable_telemetry    = var.enable_telemetry
  location            = azurerm_resource_group.this.location
  name                = "nsg-ml-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.default_tags
}

# Network Security Group - Compute Subnet
module "nsg_compute" {
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "0.5.1"

  enable_telemetry    = var.enable_telemetry
  location            = azurerm_resource_group.this.location
  name                = "nsg-compute-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.default_tags
}

# Network Security Group - Private Endpoints Subnet
module "nsg_pe" {
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "0.5.1"

  enable_telemetry    = var.enable_telemetry
  location            = azurerm_resource_group.this.location
  name                = "nsg-pe-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.default_tags
}

# Network Security Group - WireGuard VPN Gateway Subnet
module "nsg_wireguard" {
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "0.5.1"

  enable_telemetry    = var.enable_telemetry
  location            = azurerm_resource_group.this.location
  name                = "nsg-wireguard-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.default_tags

  security_rules = {
    allow_wireguard_inbound = {
      name                       = "AllowWireGuardInbound"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Udp"
      source_port_range          = "*"
      destination_port_range     = "51820"
      source_address_prefix      = "*" # clients connect from the internet
      destination_address_prefix = "*"
    }
  }
}

# Virtual Network with dedicated subnets
module "vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.17.1"

  address_space    = toset(var.vnet_address_space)
  enable_telemetry = var.enable_telemetry
  location         = azurerm_resource_group.this.location
  name             = "vnet-${local.name_prefix}"
  parent_id        = azurerm_resource_group.this.id
  tags             = local.default_tags

  subnets = {
    snet-ml = {
      name             = "snet-ml-${local.name_prefix}-${var.instance}"
      address_prefixes = [var.subnet_prefixes.ml]
      network_security_group = {
        id = module.nsg_ml.resource_id
      }
    }
    snet-compute = {
      name             = "snet-compute-${local.name_prefix}-${var.instance}"
      address_prefixes = [var.subnet_prefixes.compute]
      network_security_group = {
        id = module.nsg_compute.resource_id
      }
    }
    snet-pe = {
      name                              = "snet-pe-${local.name_prefix}-${var.instance}"
      address_prefixes                  = [var.subnet_prefixes.pe]
      private_endpoint_network_policies = "Disabled"
      network_security_group = {
        id = module.nsg_pe.resource_id
      }
    }
    snet-wireguard = {
      name             = "snet-wireguard-${local.name_prefix}-${var.instance}"
      address_prefixes = [var.subnet_prefixes.wireguard]
      network_security_group = {
        id = module.nsg_wireguard.resource_id
      }
    }
  }
}

# Private DNS Zones for Private Endpoints
resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.default_tags
}

resource "azurerm_private_dns_zone" "file" {
  name                = "privatelink.file.core.windows.net"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.default_tags
}

resource "azurerm_private_dns_zone" "vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.default_tags
}

resource "azurerm_private_dns_zone" "acr" {
  name                = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.default_tags
}

resource "azurerm_private_dns_zone" "ml_api" {
  name                = "privatelink.api.azureml.ms"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.default_tags
}

resource "azurerm_private_dns_zone" "ml_notebooks" {
  name                = "privatelink.notebooks.azure.net"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.default_tags
}

# Link Private DNS Zones to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "link-blob"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = module.vnet.resource_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "file" {
  name                  = "link-file"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.file.name
  virtual_network_id    = module.vnet.resource_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "vault" {
  name                  = "link-vault"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.vault.name
  virtual_network_id    = module.vnet.resource_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  name                  = "link-acr"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.acr.name
  virtual_network_id    = module.vnet.resource_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "ml_api" {
  name                  = "link-ml-api"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.ml_api.name
  virtual_network_id    = module.vnet.resource_id
}

resource "azurerm_private_dns_zone_virtual_network_link" "ml_notebooks" {
  name                  = "link-ml-notebooks"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.ml_notebooks.name
  virtual_network_id    = module.vnet.resource_id
}
