# -----------------------------------------------------------------------------
# Network Security Group — WireGuard VPN Gateway Subnet
# -----------------------------------------------------------------------------
module "nsg_wireguard" {
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "0.5.1"

  location            = azurerm_resource_group.this.location
  name                = local.resource_names.nsg_wireguard
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags

  security_rules = {
    allow_wireguard_inbound = {
      name                       = "AllowWireGuardInbound"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Udp"
      source_port_range          = "*"
      destination_port_range     = "51820"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  }
}

# -----------------------------------------------------------------------------
# WireGuard VPN Gateway VM (AVM)
# cloud-init installs WireGuard + dnsmasq on first boot.
# Required for accessing the private ARO API server and console.
# dnsmasq forwards DNS to Azure DNS (168.63.129.16) enabling resolution
# of privatelink.*.aroapp.io and other private DNS zones.
# -----------------------------------------------------------------------------
module "wireguard_vm" {
  source  = "Azure/avm-res-compute-virtualmachine/azurerm"
  version = "0.20.0"

  computer_name       = "vm-wireguard"
  location            = azurerm_resource_group.this.location
  name                = "vm-wg-${local.name_prefix}-${var.location}-001"
  os_type             = "Linux"
  resource_group_name = azurerm_resource_group.this.name
  sku_size            = var.vm_size
  tags                = local.tags
  zone                = var.vm_zone

  custom_data = base64encode(templatefile("${path.module}/cloud-init-wireguard.yaml.tpl", {
    server_private_key = var.wireguard_server_private_key
    client_public_key  = var.wireguard_client_public_key
    vnet_cidr          = var.vnet_address_space[0]
  }))

  account_credentials = {
    admin_credentials = {
      username                           = var.vm_admin_username
      generate_admin_password_or_ssh_key = true
    }
  }

  network_interfaces = {
    nic0 = {
      name                  = "nic-01-vm-wg-${local.name_prefix}-${var.location}-001"
      ip_forwarding_enabled = true # required for WireGuard to route packets into the VNET
      ip_configurations = {
        ipconfig1 = {
          name                          = "ipconfig1"
          private_ip_subnet_resource_id = module.vnet.subnets["wireguard"].resource_id
          create_public_ip_address      = true
          public_ip_address_name        = "pip-vm-wg-${local.name_prefix}-${var.location}-001"
        }
      }
    }
  }

  encryption_at_host_enabled = false

  os_disk = {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference = {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

# Resolve the public IP so it can be surfaced as an output
data "azurerm_public_ip" "wireguard" {
  name                = "pip-vm-wg-${local.name_prefix}-${var.location}-001"
  resource_group_name = azurerm_resource_group.this.name
  depends_on          = [module.wireguard_vm]
}
