module "wireguard_vm" {
  source  = "Azure/avm-res-compute-virtualmachine/azurerm"
  version = "0.20.0"

  computer_name       = "vm-wireguard"
  enable_telemetry    = var.enable_telemetry
  location            = azurerm_resource_group.this.location
  name                = "vm-wireguard-${local.name_prefix}-${var.instance}"
  os_type             = "Linux"
  resource_group_name = azurerm_resource_group.this.name
  sku_size            = var.vm_size
  tags                = local.default_tags
  zone                = var.vm_zone

  # cloud-init installs WireGuard and writes /etc/wireguard/wg0.conf on first boot
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
      name                  = "nic-wireguard-${local.name_prefix}-${var.instance}"
      ip_forwarding_enabled = true
      ip_configurations = {
        ipconfig1 = {
          name                          = "ipconfig1"
          private_ip_subnet_resource_id = module.vnet.subnets["snet-wireguard"].resource_id
          create_public_ip_address      = false
          public_ip_address_resource_id = azurerm_public_ip.wireguard.id
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

# Declared externally (instead of letting the AVM VM module create it) so we
# can attach lifecycle.ignore_changes = [ip_tags]. Azure auto-stamps the
# FirstPartyUsage="/Unprivileged" tag on first-party PIPs (e.g., WireGuard
# VMs), and the AVM PIP resource neither exposes `ip_tags` nor ignores it —
# so every plan would otherwise mark the PIP for REPLACEMENT, which would
# change the public IP and break wg0.conf.
resource "azurerm_public_ip" "wireguard" {
  name                    = "pip-wireguard-${local.name_prefix}-${var.instance}"
  resource_group_name     = azurerm_resource_group.this.name
  location                = azurerm_resource_group.this.location
  allocation_method       = "Static"
  sku                     = "Standard"
  sku_tier                = "Regional"
  ip_version              = "IPv4"
  ddos_protection_mode    = "VirtualNetworkInherited"
  idle_timeout_in_minutes = 30
  zones                   = ["1", "2", "3"]
  tags                    = local.default_tags

  lifecycle {
    ignore_changes = [ip_tags]
  }
}

# Resolve the public IP so it can be surfaced as an output.
# No depends_on needed: the PIP has allocation_method=Static, so its IP is
# known at create time — the VM attachment doesn't change it.
data "azurerm_public_ip" "wireguard" {
  name                = azurerm_public_ip.wireguard.name
  resource_group_name = azurerm_resource_group.this.name
}
