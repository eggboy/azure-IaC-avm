# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------
resource "azurerm_resource_group" "this" {
  location = var.location
  name     = "rg-${local.name_prefix}-${var.location}"
  tags     = local.default_tags
}

# -----------------------------------------------------------------------------
# Network Security Group — VM Subnet
# Allow SSH inbound only; all other inbound denied by default
# -----------------------------------------------------------------------------
module "nsg" {
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "0.5.1"

  enable_telemetry    = var.enable_telemetry
  location            = azurerm_resource_group.this.location
  name                = "nsg-${local.name_prefix}-${var.location}"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.default_tags

  security_rules = {
    allow_ssh_inbound = {
      name                       = "AllowSSHInbound"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefix      = var.allowed_source_ip
      destination_address_prefix = "*"
    }
  }
}

# -----------------------------------------------------------------------------
# Virtual Network with VM Subnet
# -----------------------------------------------------------------------------
module "vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.17.1"

  address_space    = var.vnet_address_space
  enable_telemetry = var.enable_telemetry
  location         = azurerm_resource_group.this.location
  name             = "vnet-${local.name_prefix}-${var.location}"
  parent_id        = azurerm_resource_group.this.id
  tags             = local.default_tags

  subnets = {
    vm = {
      name             = "snet-vm-${local.name_prefix}-${var.location}"
      address_prefixes = [var.subnet_address_prefix]
      network_security_group = {
        id = module.nsg.resource_id
      }
    }
  }
}
