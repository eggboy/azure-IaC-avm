# -----------------------------------------------------------------------------
# Azure Red Hat OpenShift — Private Cluster (AVM)
# API server and Ingress both set to Private visibility.
# Uses managed identities (no service principal) with platform workload
# identity federation for operator components.
#
# Module: Azure/avm-res-redhatopenshift-openshiftcluster/azurerm
# Reference: https://github.com/Azure/terraform-azurerm-avm-res-redhatopenshift-openshiftcluster
# -----------------------------------------------------------------------------
module "aro" {
  source  = "Azure/avm-res-redhatopenshift-openshiftcluster/azurerm"
  version = "0.0.2"

  name                = local.resource_names.aro
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags

  # Private API server — accessible only via private endpoint within the VNet
  api_server_profile = {
    visibility = "Private"
  }

  # Cluster profile — domain, version, optional pull secret
  cluster_profile = {
    domain      = local.resource_names.aro_domain
    version     = var.aro_cluster_version
    pull_secret = var.pull_secret
  }

  # Private ingress — cluster routes are not exposed publicly
  ingress_profile = {
    visibility = "Private"
  }

  # Master (control plane) node profile
  main_profile = {
    subnet_id = module.vnet.subnets["master"].resource_id
    vm_size   = var.aro_master_vm_size
  }

  # Network profile — pod and service CIDRs
  network_profile = {
    pod_cidr     = "10.128.0.0/14"
    service_cidr = "172.30.0.0/16"
  }

  # Worker node pool profile
  worker_profile = {
    subnet_id    = module.vnet.subnets["worker"].resource_id
    vm_size      = var.aro_worker_vm_size
    node_count   = var.aro_worker_node_count
    disk_size_gb = var.aro_worker_disk_size_gb
  }

  # Managed identity — cluster-level user-assigned identity
  managed_identities = {
    user_assigned_resource_ids = toset([
      azurerm_user_assigned_identity.cluster.id
    ])
  }

  # Platform workload identities — operator-level identities for federation
  platform_workload_identities = {
    for name, identity in azurerm_user_assigned_identity.platform : name => {
      resource_id = identity.id
    }
  }

  # Provide subscription ID to avoid replacement drift at plan time
  subscription_id = data.azurerm_client_config.current.subscription_id

  enable_telemetry = true

  timeouts = {
    create = "120m"
    delete = "120m"
    update = "120m"
  }

  depends_on = [
    azurerm_role_assignment.cluster_over_platform,
    azurerm_role_assignment.platform_network,
    azurerm_role_assignment.rp_network_contributor,
  ]
}
