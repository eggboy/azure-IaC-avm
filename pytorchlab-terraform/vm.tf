# -----------------------------------------------------------------------------
# GPU Linux VM (AVM)
# NVIDIA T4 with Ubuntu 24.04 LTS, CUDA drivers via Azure VM extension,
# PyTorch + Jupyter installed via cloud-init
# -----------------------------------------------------------------------------
module "vm" {
  source  = "Azure/avm-res-compute-virtualmachine/azurerm"
  version = "0.20.0"

  computer_name              = "vm-gpu"
  enable_telemetry           = var.enable_telemetry
  encryption_at_host_enabled = false
  location                   = azurerm_resource_group.this.location
  name                       = "vm-${local.name_prefix}-${var.location}"
  os_type                    = "Linux"
  resource_group_name        = azurerm_resource_group.this.name
  sku_size                   = var.vm_size
  tags                       = local.default_tags
  zone                       = var.vm_zone

  # Spot VM bypasses MCAPS SKU deny policy and reduces cost by ~60-90%
  eviction_policy = var.spot_enabled ? "Deallocate" : null
  max_bid_price   = var.spot_enabled ? -1 : null
  priority        = var.spot_enabled ? "Spot" : "Regular"

  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tpl", {
    admin_username = var.admin_username
  }))

  account_credentials = {
    admin_credentials = {
      username                           = var.admin_username
      ssh_keys                           = [file(pathexpand(var.ssh_public_key_file))]
      generate_admin_password_or_ssh_key = false
    }
  }

  managed_identities = {
    system_assigned = true
  }

  network_interfaces = {
    nic0 = {
      name = "nic-01-vm-${local.name_prefix}-${var.location}"
      ip_configurations = {
        ipconfig1 = {
          name                          = "ipconfig1"
          private_ip_subnet_resource_id = module.vnet.subnets["vm"].resource_id
          create_public_ip_address      = true
          public_ip_address_name        = "pip-vm-${local.name_prefix}-${var.location}"
        }
      }
    }
  }

  os_disk = {
    caching              = "ReadWrite"
    disk_size_gb         = var.os_disk_size_gb
    storage_account_type = "Premium_LRS"
  }

  source_image_reference = {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  extensions = {
    nvidia_gpu_driver = {
      name                 = "NvidiaGpuDriverLinux"
      publisher            = "Microsoft.HpcCompute"
      type                 = "NvidiaGpuDriverLinux"
      type_handler_version = "1.13"
    }
  }
}

# Resolve the public IP so it can be surfaced as an output
data "azurerm_public_ip" "vm" {
  name                = "pip-vm-${local.name_prefix}-${var.location}"
  resource_group_name = azurerm_resource_group.this.name

  depends_on = [module.vm]
}
