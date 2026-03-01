# -----------------------------------------------------------------------------
# Public IP for Azure Firewall
# -----------------------------------------------------------------------------
resource "azurerm_public_ip" "firewall" {
  allocation_method   = "Static"
  location            = azurerm_resource_group.this.location
  name                = local.resource_names.public_ip_firewall
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "Standard"
  tags                = local.tags
  zones               = ["1", "2", "3"]
}

# -----------------------------------------------------------------------------
# Azure Firewall Policy (AVM)
# -----------------------------------------------------------------------------
module "firewall_policy" {
  source  = "Azure/avm-res-network-firewallpolicy/azurerm"
  version = "0.3.4"

  location            = azurerm_resource_group.this.location
  name                = local.resource_names.firewall_policy
  resource_group_name = azurerm_resource_group.this.name

  firewall_policy_sku = "Standard"

  firewall_policy_dns = {
    proxy_enabled = true
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Azure Firewall (AVM)
# -----------------------------------------------------------------------------
module "firewall" {
  source  = "Azure/avm-res-network-azurefirewall/azurerm"
  version = "0.4.0"

  location            = azurerm_resource_group.this.location
  name                = local.resource_names.firewall
  resource_group_name = azurerm_resource_group.this.name

  firewall_sku_name = "AZFW_VNet"
  firewall_sku_tier = "Standard"
  firewall_zones    = ["1", "2", "3"]

  firewall_policy_id = module.firewall_policy.resource_id

  ip_configurations = {
    default = {
      name                 = "fw-ipconfig"
      public_ip_address_id = azurerm_public_ip.firewall.id
      subnet_id            = module.vnet.subnets["firewall"].resource_id
    }
  }

  diagnostic_settings = {
    to_log_analytics = {
      name                  = "fw-diagnostics"
      workspace_resource_id = module.log_analytics.resource_id
    }
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Firewall Policy Rule Collection Group - Network Rules
# Azure Global required network rules per:
# https://learn.microsoft.com/en-us/azure/aks/outbound-rules-control-egress
# -----------------------------------------------------------------------------
resource "azurerm_firewall_policy_rule_collection_group" "aks_network_rules" {
  firewall_policy_id = module.firewall_policy.resource_id
  name               = "aks-network-rules"
  priority           = 100

  # ---------------------------------------------------------------------------
  # Azure Global required network rules
  # ---------------------------------------------------------------------------
  network_rule_collection {
    action   = "Allow"
    name     = "aks-global-required"
    priority = 100

    rule {
      name                  = "apiserver-udp"
      destination_addresses = ["AzureCloud.${var.location}"]
      destination_ports     = ["1194"]
      protocols             = ["UDP"]
      source_addresses      = ["*"]
    }
    rule {
      name                  = "apiserver-tcp"
      destination_addresses = ["AzureCloud.${var.location}"]
      destination_ports     = ["9000"]
      protocols             = ["TCP"]
      source_addresses      = ["*"]
    }
    rule {
      name              = "ntp"
      destination_fqdns = ["ntp.ubuntu.com"]
      destination_ports = ["123"]
      protocols         = ["UDP"]
      source_addresses  = ["*"]
    }
  }

  # ---------------------------------------------------------------------------
  # Azure Monitor - required network rule (ServiceTag)
  # ---------------------------------------------------------------------------
  network_rule_collection {
    action   = "Allow"
    name     = "azure-monitor-network"
    priority = 200

    rule {
      name                  = "azure-monitor"
      destination_addresses = ["AzureMonitor"]
      destination_ports     = ["443"]
      protocols             = ["TCP"]
      source_addresses      = ["*"]
    }
  }

  # ---------------------------------------------------------------------------
  # Container registries (workshop extras)
  # ---------------------------------------------------------------------------
  network_rule_collection {
    action   = "Allow"
    name     = "container-registries"
    priority = 300

    rule {
      name              = "ghcr"
      destination_fqdns = ["ghcr.io", "pkg-containers.githubusercontent.com"]
      destination_ports = ["443"]
      protocols         = ["TCP"]
      source_addresses  = ["*"]
    }
    rule {
      name              = "docker"
      destination_fqdns = ["docker.io", "registry-1.docker.io", "production.cloudflare.docker.com"]
      destination_ports = ["443"]
      protocols         = ["TCP"]
      source_addresses  = ["*"]
    }
  }

  # ---------------------------------------------------------------------------
  # Git SSH & SMB fileshare (workshop extras)
  # ---------------------------------------------------------------------------
  network_rule_collection {
    action   = "Allow"
    name     = "git-ssh"
    priority = 400

    rule {
      name                  = "git-ssh"
      destination_addresses = ["*"]
      destination_ports     = ["22"]
      protocols             = ["TCP"]
      source_addresses      = ["*"]
    }
  }

  network_rule_collection {
    action   = "Allow"
    name     = "fileshare"
    priority = 500

    rule {
      name                  = "smb"
      destination_addresses = ["*"]
      destination_ports     = ["445"]
      protocols             = ["TCP"]
      source_addresses      = ["*"]
    }
  }
}

# -----------------------------------------------------------------------------
# Firewall Policy Rule Collection Group - Application Rules
# Azure Global required + optional + GPU + all features/addons/integrations
# https://learn.microsoft.com/en-us/azure/aks/outbound-rules-control-egress
# -----------------------------------------------------------------------------
resource "azurerm_firewall_policy_rule_collection_group" "aks_application_rules" {
  firewall_policy_id = module.firewall_policy.resource_id
  name               = "aks-application-rules"
  priority           = 200

  # ---------------------------------------------------------------------------
  # AzureKubernetesService FQDN tag (covers most core AKS FQDNs)
  # ---------------------------------------------------------------------------
  application_rule_collection {
    action   = "Allow"
    name     = "aks-fqdn-tags"
    priority = 100

    rule {
      name             = "aks-service-tag"
      source_addresses = ["*"]

      protocols {
        port = 80
        type = "Http"
      }
      protocols {
        port = 443
        type = "Https"
      }

      destination_fqdn_tags = ["AzureKubernetesService"]
    }
  }

  # ---------------------------------------------------------------------------
  # Azure Global required FQDN / application rules
  # ---------------------------------------------------------------------------
  application_rule_collection {
    action   = "Allow"
    name     = "aks-global-required-fqdns"
    priority = 200

    rule {
      name             = "aks-api-server"
      source_addresses = ["*"]

      protocols {
        port = 443
        type = "Https"
      }

      destination_fqdns = [
        "*.hcp.${var.location}.azmk8s.io",
      ]
    }
    rule {
      name             = "mcr"
      source_addresses = ["*"]

      protocols {
        port = 443
        type = "Https"
      }

      destination_fqdns = [
        "mcr.microsoft.com",
        "*.data.mcr.microsoft.com",
        "mcr-0001.mcr-msedge.net",
      ]
    }
    rule {
      name             = "management-and-auth"
      source_addresses = ["*"]

      protocols {
        port = 443
        type = "Https"
      }

      destination_fqdns = [
        "management.azure.com",
        "login.microsoftonline.com",
      ]
    }
    rule {
      name             = "packages"
      source_addresses = ["*"]

      protocols {
        port = 443
        type = "Https"
      }

      destination_fqdns = [
        "packages.microsoft.com",
        "acs-mirror.azureedge.net",
        "packages.aks.azure.com",
      ]
    }
  }

  # ---------------------------------------------------------------------------
  # Optional recommended FQDN / application rules
  # ---------------------------------------------------------------------------
  application_rule_collection {
    action   = "Allow"
    name     = "aks-optional-recommended"
    priority = 300

    rule {
      name             = "ubuntu-updates"
      source_addresses = ["*"]

      protocols {
        port = 80
        type = "Http"
      }

      destination_fqdns = [
        "security.ubuntu.com",
        "azure.archive.ubuntu.com",
        "changelogs.ubuntu.com",
      ]
    }
    rule {
      name             = "ubuntu-snapshots"
      source_addresses = ["*"]

      protocols {
        port = 443
        type = "Https"
      }

      destination_fqdns = [
        "snapshot.ubuntu.com",
      ]
    }
  }

  # ---------------------------------------------------------------------------
  # GPU enabled AKS clusters required FQDN / application rules
  # ---------------------------------------------------------------------------
  application_rule_collection {
    action   = "Allow"
    name     = "aks-gpu-required"
    priority = 400

    rule {
      name             = "nvidia-gpu"
      source_addresses = ["*"]

      protocols {
        port = 443
        type = "Https"
      }

      destination_fqdns = [
        "nvidia.github.io",
        "us.download.nvidia.com",
        "download.docker.com",
      ]
    }
  }

  # ---------------------------------------------------------------------------
  # Microsoft Defender for Containers
  # ---------------------------------------------------------------------------
  application_rule_collection {
    action   = "Allow"
    name     = "defender-for-containers"
    priority = 500

    rule {
      name             = "defender-fqdns"
      source_addresses = ["*"]

      protocols {
        port = 443
        type = "Https"
      }

      destination_fqdns = [
        "login.microsoftonline.com",
        "*.ods.opinsights.azure.com",
        "*.oms.opinsights.azure.com",
        "*.cloud.defender.microsoft.com",
      ]
    }
  }

  # ---------------------------------------------------------------------------
  # Azure Key Vault provider for Secrets Store CSI Driver
  # (also required by Istio service mesh add-on & Application routing add-on)
  # ---------------------------------------------------------------------------
  application_rule_collection {
    action   = "Allow"
    name     = "keyvault-csi-driver"
    priority = 600

    rule {
      name             = "keyvault"
      source_addresses = ["*"]

      protocols {
        port = 443
        type = "Https"
      }

      destination_fqdns = [
        "vault.azure.net",
      ]
    }
  }

  # ---------------------------------------------------------------------------
  # Azure Monitor - Managed Prometheus, Container Insights, App Insights
  # ---------------------------------------------------------------------------
  application_rule_collection {
    action   = "Allow"
    name     = "azure-monitor-fqdns"
    priority = 700

    rule {
      name             = "azure-monitor"
      source_addresses = ["*"]

      protocols {
        port = 443
        type = "Https"
      }

      destination_fqdns = [
        "*.ods.opinsights.azure.com",
        "*.oms.opinsights.azure.com",
        "dc.services.visualstudio.com",
        "*.in.applicationinsights.azure.com",
        "*.monitoring.azure.com",
        "login.microsoftonline.com",
        "global.handler.control.monitor.azure.com",
        "${var.location}.handler.control.monitor.azure.com",
        "*.ingest.monitor.azure.com",
        "*.metrics.ingest.monitor.azure.com",
      ]
    }
  }

  # ---------------------------------------------------------------------------
  # Azure Policy
  # ---------------------------------------------------------------------------
  application_rule_collection {
    action   = "Allow"
    name     = "azure-policy"
    priority = 800

    rule {
      name             = "azure-policy-fqdns"
      source_addresses = ["*"]

      protocols {
        port = 443
        type = "Https"
      }

      destination_fqdns = [
        "data.policy.core.windows.net",
        "store.policy.core.windows.net",
        "dc.services.visualstudio.com",
      ]
    }
  }

  # ---------------------------------------------------------------------------
  # Cluster extensions (incl. marketplace extensions)
  # ---------------------------------------------------------------------------
  application_rule_collection {
    action   = "Allow"
    name     = "cluster-extensions"
    priority = 900

    rule {
      name             = "extensions-config"
      source_addresses = ["*"]

      protocols {
        port = 443
        type = "Https"
      }

      destination_fqdns = [
        "${var.location}.dp.kubernetesconfiguration.azure.com",
        "mcr.microsoft.com",
        "*.data.mcr.microsoft.com",
      ]
    }
    rule {
      name             = "marketplace-extensions"
      source_addresses = ["*"]

      protocols {
        port = 443
        type = "Https"
      }

      destination_fqdns = [
        "arcmktplaceprod.azurecr.io",
        "arcmktplaceprod.centralindia.data.azurecr.io",
        "arcmktplaceprod.japaneast.data.azurecr.io",
        "arcmktplaceprod.westus2.data.azurecr.io",
        "arcmktplaceprod.westeurope.data.azurecr.io",
        "arcmktplaceprod.eastus.data.azurecr.io",
      ]
    }
    rule {
      name             = "extensions-telemetry"
      source_addresses = ["*"]

      protocols {
        port = 443
        type = "Https"
      }

      destination_fqdns = [
        "*.ingestion.msftcloudes.com",
        "*.microsoftmetrics.com",
        "marketplaceapi.microsoft.com",
      ]
    }
  }

  # ---------------------------------------------------------------------------
  # Workshop extras (from sg-aks-workshop)
  # ---------------------------------------------------------------------------
  application_rule_collection {
    action   = "Allow"
    name     = "workshop-extras"
    priority = 1000

    rule {
      name             = "additional-registries"
      source_addresses = ["*"]

      protocols {
        port = 443
        type = "Https"
      }
      protocols {
        port = 80
        type = "Http"
      }

      destination_fqdns = [
        "*.blob.core.windows.net",
        "*github.com",
        "*quay.io",
        "*letsencrypt.org",
        "*gcr.io",
        "*googleapis.com",
      ]
    }
  }
}
