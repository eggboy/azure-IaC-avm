# -----------------------------------------------------------------------------
# User-Assigned Managed Identity — ARO Cluster Identity
# The cluster identity that manages the ARO cluster lifecycle
# -----------------------------------------------------------------------------
resource "azurerm_user_assigned_identity" "cluster" {
  location            = azurerm_resource_group.this.location
  name                = "id-aro-cluster-${local.name_prefix}-${var.location}-001"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

# -----------------------------------------------------------------------------
# User-Assigned Managed Identities — Platform Workload Identities
# Operator identities required for ARO platform components:
#   aro-operator, cloud-controller-manager, cloud-network-config,
#   disk-csi-driver, file-csi-driver, image-registry, ingress, machine-api
# -----------------------------------------------------------------------------
resource "azurerm_user_assigned_identity" "platform" {
  for_each = toset(local.platform_identity_names)

  location            = azurerm_resource_group.this.location
  name                = "id-${each.value}-${local.name_prefix}-${var.location}-001"
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

# -----------------------------------------------------------------------------
# Cluster → Platform Identity: Federated Credential Role
# The cluster identity must be able to issue federated credentials for each
# operator identity to enable workload identity federation within the cluster.
# -----------------------------------------------------------------------------
resource "azurerm_role_assignment" "cluster_over_platform" {
  for_each = azurerm_user_assigned_identity.platform

  principal_id                     = azurerm_user_assigned_identity.cluster.principal_id
  scope                            = each.value.id
  principal_type                   = "ServicePrincipal"
  role_definition_name             = "Azure Red Hat OpenShift Federated Credential"
  skip_service_principal_aad_check = true
}

# -----------------------------------------------------------------------------
# Platform Identity → Network: Operator-specific Role Assignments
# Each platform identity gets minimum required permissions on VNet/Subnet scope.
# Flatten the nested map into individual role assignments.
# -----------------------------------------------------------------------------
resource "azurerm_role_assignment" "platform_network" {
  for_each = {
    for binding in flatten([
      for identity_key, value in local.platform_network_role_bindings : [
        for scope_key, scope_id in value.scopes : {
          identity_key         = identity_key
          scope_key            = scope_key
          role_definition_name = value.role_definition_name
          scope                = scope_id
          key                  = format("%s-%s", identity_key, scope_key)
        }
      ]
    ]) : binding.key => binding
  }

  principal_id                     = azurerm_user_assigned_identity.platform[each.value.identity_key].principal_id
  scope                            = each.value.scope
  principal_type                   = "ServicePrincipal"
  role_definition_name             = each.value.role_definition_name
  skip_service_principal_aad_check = true
}

# -----------------------------------------------------------------------------
# ARO Resource Provider → VNet: Network Contributor
# The first-party Azure Red Hat OpenShift RP service principal needs
# Network Contributor on the VNet to manage cluster networking.
# -----------------------------------------------------------------------------
resource "azurerm_role_assignment" "rp_network_contributor" {
  principal_id                     = data.azuread_service_principal.aro_rp.object_id
  scope                            = module.vnet.resource_id
  principal_type                   = "ServicePrincipal"
  role_definition_name             = "Network Contributor"
  skip_service_principal_aad_check = true
}
