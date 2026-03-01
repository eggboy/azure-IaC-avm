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
      generate_admin_password_or_ssh_key = true # generates an SSH key pair; private key in Terraform state
    }
  }

  network_interfaces = {
    nic0 = {
      name                  = "nic-01-vm-wireguard-${local.name_prefix}-${var.instance}"
      ip_forwarding_enabled = true # required for WireGuard to route packets into the VNET
      ip_configurations = {
        ipconfig1 = {
          name                          = "ipconfig1"
          private_ip_subnet_resource_id = module.vnet.subnets["snet-wireguard"].resource_id
          create_public_ip_address      = true
          public_ip_address_name        = "pip-vm-wireguard-${var.environment}-${var.location}-${var.instance}"
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
  name                = "pip-vm-wireguard-${var.environment}-${var.location}-${var.instance}"
  resource_group_name = azurerm_resource_group.this.name
  depends_on          = [module.wireguard_vm]
}
