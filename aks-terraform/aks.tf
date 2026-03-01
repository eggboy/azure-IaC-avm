# -----------------------------------------------------------------------------
# User-Assigned Managed Identity for AKS Control Plane
# Required for private cluster with custom private DNS zone
# -----------------------------------------------------------------------------
resource "azurerm_user_assigned_identity" "aks" {
  location            = azurerm_resource_group.this.location
  name                = local.resource_names.aks_identity
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

# AKS identity → Private DNS Zone Contributor on the AKS private DNS zone
resource "azurerm_role_assignment" "aks_dns_contributor" {
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
  role_definition_name = "Private DNS Zone Contributor"
  scope                = azurerm_private_dns_zone.aks.id
}

# AKS identity → Network Contributor on the VNet (required for UDR + private cluster)
resource "azurerm_role_assignment" "aks_network_contributor" {
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
  role_definition_name = "Network Contributor"
  scope                = module.vnet.resource_id
}

# -----------------------------------------------------------------------------
# Private DNS Zone for AKS API Server
# Enables resolution of the private AKS API endpoint from the VNET
# (WireGuard dnsmasq → Azure DNS 168.63.129.16 → this zone)
# -----------------------------------------------------------------------------
resource "azurerm_private_dns_zone" "aks" {
  name                = "privatelink.${var.location}.azmk8s.io"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "aks" {
  name                  = "link-aks"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.aks.name
  virtual_network_id    = module.vnet.resource_id
}

# -----------------------------------------------------------------------------
# AKS Managed Cluster (AVM)
# Private cluster with Azure CNI Overlay + Cilium, UDR through Azure Firewall
# Reference: az aks create from sg-aks-workshop
# -----------------------------------------------------------------------------
module "aks" {
  source  = "Azure/avm-res-containerservice-managedcluster/azurerm"
  version = "0.5.2"

  name      = local.resource_names.aks
  location  = azurerm_resource_group.this.location
  parent_id = azurerm_resource_group.this.id
  tags      = local.tags

  kubernetes_version = var.kubernetes_version

  # User-assigned managed identity (required for custom private DNS zone)
  managed_identities = {
    user_assigned_resource_ids = [azurerm_user_assigned_identity.aks.id]
  }

  # AAD (Entra ID) integration with Azure RBAC — matches --enable-aad
  aad_profile = {
    managed           = true
    enable_azure_rbac = true
  }

  # Private cluster — API server only accessible via private endpoint
  api_server_access_profile = {
    enable_private_cluster             = true
    enable_private_cluster_public_fqdn = false
    private_dns_zone                   = azurerm_private_dns_zone.aks.id
  }

  # Enable local accounts
  disable_local_accounts = false

  # OIDC issuer — matches --enable-oidc-issuer (required for workload identity)
  oidc_issuer_profile = {
    enabled = true
  }

  # Workload identity + image cleaner
  security_profile = {
    workload_identity = {
      enabled = true
    }
    image_cleaner = {
      enabled        = true
      interval_hours = 48
    }
  }

  # VPA — matches --enable-vpa
  workload_auto_scaler_profile = {
    vertical_pod_autoscaler = {
      enabled = true
    }
  }

  # Key Vault Secrets Provider addon — matches --enable-addons azure-keyvault-secrets-provider
  addon_profile_key_vault_secrets_provider = {
    enabled = true
    config = {
      enable_secret_rotation = true
      rotation_poll_interval = "2m"
    }
  }

  # Container Insights via OMS Agent → Log Analytics
  addon_profile_oms_agent = {
    enabled = true
    config = {
      log_analytics_workspace_resource_id = module.log_analytics.resource_id
      use_aad_auth                        = true
    }
  }

  # Azure Policy addon
  addon_profile_azure_policy = {
    enabled = true
  }

  # Network profile — Azure CNI Overlay + Cilium + UDR through Firewall
  # Matches: --network-plugin azure --network-dataplane cilium
  #          --service-cidr 10.10.0.0/24 --dns-service-ip 10.10.0.10
  #          --load-balancer-backend-pool-type=nodeIP
  network_profile = {
    network_plugin      = "azure"
    network_dataplane   = "cilium"
    network_plugin_mode = "overlay"
    network_policy      = "cilium"
    dns_service_ip      = "10.10.0.10"
    service_cidr        = "10.10.0.0/24"
    outbound_type       = "userDefinedRouting"
  }

  # Default system node pool — matches --node-count 1 --node-vm-size --max-pods 110
  default_agent_pool = {
    name           = "system"
    count_of       = 1
    vm_size        = var.aks_node_vm_size
    max_pods       = 110
    vnet_subnet_id = module.vnet.subnets["aks"].resource_id
    os_sku         = "AzureLinux"
    upgrade_settings = {
      max_surge = "33%"
    }
  }

  # Linux profile with SSH key — matches --ssh-key-value
  linux_profile = {
    admin_username = "azureadmin"
    ssh = {
      public_keys = [
        {
          key_data = var.ssh_public_key
        }
      ]
    }
  }

  # Diagnostic settings → Log Analytics
  diagnostic_settings = {
    to_log_analytics = {
      name                  = "aks-diagnostics"
      workspace_resource_id = module.log_analytics.resource_id
    }
  }

  depends_on = [
    time_sleep.wait_for_route_table,
    azurerm_role_assignment.aks_dns_contributor,
    azurerm_role_assignment.aks_network_contributor,
  ]
}

# Wait for route table subnet association to propagate in Azure
resource "time_sleep" "wait_for_route_table" {
  create_duration = "30s"

  depends_on = [module.route_table_firewall]
}

# -----------------------------------------------------------------------------
# ACR Pull Role Assignment for AKS Kubelet Identity
# Allows the AKS cluster to pull images from the private ACR
# -----------------------------------------------------------------------------
resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = module.aks.kubelet_identity.objectId
  role_definition_name             = "AcrPull"
  scope                            = module.container_registry.resource_id
  skip_service_principal_aad_check = true
}
