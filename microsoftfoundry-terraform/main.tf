# Random suffix for globally unique resource names
resource "random_string" "suffix" {
  length  = 4
  numeric = true
  special = false
  upper   = false
}

# Resource Group
resource "azurerm_resource_group" "this" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.default_tags
}

# ----- Network Security Groups -----

# NSG - Agent Subnet
module "nsg_agent" {
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "0.5.1"

  enable_telemetry    = var.enable_telemetry
  location            = azurerm_resource_group.this.location
  name                = "nsg-agent-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.default_tags
}

# NSG - API Management Subnet (only when APIM is enabled)
module "nsg_apim" {
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "0.5.1"
  count   = var.enable_apim ? 1 : 0

  enable_telemetry    = var.enable_telemetry
  location            = azurerm_resource_group.this.location
  name                = "nsg-apim-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.default_tags

  security_rules = {
    allow_apim_gateway_inbound = {
      name                       = "AllowAPIMGatewayInbound"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "VirtualNetwork"
    }
    allow_outbound_storage = {
      name                       = "AllowOutboundStorage"
      priority                   = 200
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "Storage"
    }
    allow_outbound_keyvault = {
      name                       = "AllowOutboundKeyVault"
      priority                   = 210
      direction                  = "Outbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "VirtualNetwork"
      destination_address_prefix = "AzureKeyVault"
    }
  }
}

# NSG - Private Endpoints Subnet
module "nsg_pe" {
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "0.5.1"

  enable_telemetry    = var.enable_telemetry
  location            = azurerm_resource_group.this.location
  name                = "nsg-pe-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.default_tags
}

# NSG - MCP Subnet
module "nsg_mcp" {
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "0.5.1"

  enable_telemetry    = var.enable_telemetry
  location            = azurerm_resource_group.this.location
  name                = "nsg-mcp-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.default_tags
}

# NSG - WireGuard VPN Gateway Subnet
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
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  }
}

# ----- Virtual Network -----

module "vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.17.1"

  address_space    = toset(var.vnet_address_space)
  enable_telemetry = var.enable_telemetry
  location         = azurerm_resource_group.this.location
  name             = "vnet-${local.name_prefix}"
  parent_id        = azurerm_resource_group.this.id
  tags             = local.default_tags

  subnets = merge(
    {
      snet-agent = {
        name             = "snet-agent-${local.name_prefix}-${var.instance}"
        address_prefixes = [var.subnet_prefixes.agent]
        delegations = [{
          name = "Microsoft.App.environments"
          service_delegation = {
            name = "Microsoft.App/environments"
          }
        }]
        network_security_group = {
          id = module.nsg_agent.resource_id
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
      snet-mcp = {
        name             = "snet-mcp-${local.name_prefix}-${var.instance}"
        address_prefixes = [var.subnet_prefixes.mcp]
        delegations = [{
          name = "Microsoft.App.environments"
          service_delegation = {
            name = "Microsoft.App/environments"
          }
        }]
        network_security_group = {
          id = module.nsg_mcp.resource_id
        }
      }
      snet-wireguard = {
        name             = "snet-wireguard-${local.name_prefix}-${var.instance}"
        address_prefixes = [var.subnet_prefixes.wireguard]
        network_security_group = {
          id = module.nsg_wireguard.resource_id
        }
      }
    },
    var.enable_apim ? {
      snet-apim = {
        name             = "snet-apim-${local.name_prefix}-${var.instance}"
        address_prefixes = [var.subnet_prefixes.apim]
        delegations = [{
          name = "Microsoft.Web.hostingEnvironments"
          service_delegation = {
            name = "Microsoft.Web/hostingEnvironments"
          }
        }]
        network_security_group = {
          id = module.nsg_apim[0].resource_id
        }
      }
    } : {}
  )
}

# ----- Private DNS Zones (AVM modules with integrated VNet links) -----

module "dns_ai_services" {
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.5.0"

  domain_name      = "privatelink.services.ai.azure.com"
  enable_telemetry = var.enable_telemetry
  parent_id        = azurerm_resource_group.this.id
  tags             = local.default_tags

  virtual_network_links = {
    vnet = {
      name               = "link-ai-services"
      virtual_network_id = module.vnet.resource_id
    }
  }
}

module "dns_openai" {
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.5.0"

  domain_name      = "privatelink.openai.azure.com"
  enable_telemetry = var.enable_telemetry
  parent_id        = azurerm_resource_group.this.id
  tags             = local.default_tags

  virtual_network_links = {
    vnet = {
      name               = "link-openai"
      virtual_network_id = module.vnet.resource_id
    }
  }
}

module "dns_cognitive_services" {
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.5.0"

  domain_name      = "privatelink.cognitiveservices.azure.com"
  enable_telemetry = var.enable_telemetry
  parent_id        = azurerm_resource_group.this.id
  tags             = local.default_tags

  virtual_network_links = {
    vnet = {
      name               = "link-cognitive-services"
      virtual_network_id = module.vnet.resource_id
    }
  }
}

module "dns_search" {
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.5.0"

  domain_name      = "privatelink.search.windows.net"
  enable_telemetry = var.enable_telemetry
  parent_id        = azurerm_resource_group.this.id
  tags             = local.default_tags

  virtual_network_links = {
    vnet = {
      name               = "link-search"
      virtual_network_id = module.vnet.resource_id
    }
  }
}

module "dns_apim" {
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.5.0"
  count   = var.enable_apim ? 1 : 0

  domain_name      = "azure-api.net"
  enable_telemetry = var.enable_telemetry
  parent_id        = azurerm_resource_group.this.id
  tags             = local.default_tags

  virtual_network_links = {
    vnet = {
      name               = "link-apim"
      virtual_network_id = module.vnet.resource_id
    }
  }

  a_records = {
    apim_gateway = {
      name    = local.apim_name
      ttl     = 300
      records = [module.apim[0].private_ip_addresses[0]]
    }
  }
}

module "dns_blob" {
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.5.0"

  domain_name      = "privatelink.blob.core.windows.net"
  enable_telemetry = var.enable_telemetry
  parent_id        = azurerm_resource_group.this.id
  tags             = local.default_tags

  virtual_network_links = {
    vnet = {
      name               = "link-blob"
      virtual_network_id = module.vnet.resource_id
    }
  }
}

module "dns_cosmos" {
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.5.0"

  domain_name      = "privatelink.documents.azure.com"
  enable_telemetry = var.enable_telemetry
  parent_id        = azurerm_resource_group.this.id
  tags             = local.default_tags

  virtual_network_links = {
    vnet = {
      name               = "link-cosmos"
      virtual_network_id = module.vnet.resource_id
    }
  }
}
