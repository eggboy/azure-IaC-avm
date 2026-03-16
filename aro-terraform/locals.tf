locals {
  name_prefix = "${var.workload}-${var.environment}"

  # Azure CAF naming convention: <abbreviation>-<workload>-<environment>-<region>-<instance>
  resource_names = {
    aro            = "aro-${local.name_prefix}-${var.location}-001"
    aro_domain     = "aro${random_string.domain.result}"
    log_analytics  = "log-${local.name_prefix}-${var.location}-001"
    nat_gateway    = "ng-${local.name_prefix}-${var.location}-001"
    nsg_wireguard  = "nsg-wg-${local.name_prefix}-${var.location}-001"
    resource_group = "rg-${local.name_prefix}-${var.location}-001"
    vnet           = "vnet-${local.name_prefix}-${var.location}-001"
  }

  # Subnet definitions for Private ARO cluster
  subnets = {
    master = {
      address_prefixes = ["10.0.0.0/23"]
      name             = "snet-master-${local.name_prefix}-${var.location}-001"
    }
    pe = {
      address_prefixes = ["10.0.4.0/26"]
      name             = "snet-pe-${local.name_prefix}-${var.location}-001"
    }
    wireguard = {
      address_prefixes = ["10.0.4.64/26"]
      name             = "snet-wg-${local.name_prefix}-${var.location}-001"
    }
    worker = {
      address_prefixes = ["10.0.2.0/23"]
      name             = "snet-worker-${local.name_prefix}-${var.location}-001"
    }
  }

  # Managed identity names (CAF: id-<purpose>-<workload>-<env>-<region>-<instance>)
  platform_identity_names = [
    "aro-operator",
    "cloud-controller-manager",
    "cloud-network-config",
    "disk-csi-driver",
    "file-csi-driver",
    "image-registry",
    "ingress",
    "machine-api",
  ]

  # Role assignments for platform workload identities on network resources
  platform_network_role_bindings = {
    "aro-operator" = {
      role_definition_name = "Azure Red Hat OpenShift Service Operator"
      scopes = {
        master = module.vnet.subnets["master"].resource_id
        worker = module.vnet.subnets["worker"].resource_id
      }
    }
    "cloud-controller-manager" = {
      role_definition_name = "Azure Red Hat OpenShift Cloud Controller Manager"
      scopes = {
        master = module.vnet.subnets["master"].resource_id
        worker = module.vnet.subnets["worker"].resource_id
      }
    }
    "cloud-network-config" = {
      role_definition_name = "Azure Red Hat OpenShift Network Operator"
      scopes = {
        vnet = module.vnet.resource_id
      }
    }
    "file-csi-driver" = {
      role_definition_name = "Azure Red Hat OpenShift File Storage Operator"
      scopes = {
        vnet = module.vnet.resource_id
      }
    }
    "image-registry" = {
      role_definition_name = "Azure Red Hat OpenShift Image Registry Operator"
      scopes = {
        vnet = module.vnet.resource_id
      }
    }
    "ingress" = {
      role_definition_name = "Azure Red Hat OpenShift Cluster Ingress Operator"
      scopes = {
        master = module.vnet.subnets["master"].resource_id
        worker = module.vnet.subnets["worker"].resource_id
      }
    }
    "machine-api" = {
      role_definition_name = "Azure Red Hat OpenShift Machine API Operator"
      scopes = {
        master = module.vnet.subnets["master"].resource_id
        worker = module.vnet.subnets["worker"].resource_id
      }
    }
  }

  tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Workload    = var.workload
  })
}

# Random string for globally-unique ARO cluster domain
resource "random_string" "domain" {
  length  = 8
  lower   = true
  numeric = true
  special = false
  upper   = false
}
