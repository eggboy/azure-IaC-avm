# aml-avm

Azure ML Infrastructure as Code with Azure Verified Module (AVM) Terraform

## Architecture

This Terraform configuration deploys a secure Azure Machine Learning environment with the following components:

### Networking
- **Virtual Network** (`vnet-`) with dedicated subnets:
  - `snet-ml` — Azure ML workspace private endpoint
  - `snet-compute` — Azure ML serverless compute
  - `snet-pe` — Private endpoints for supporting services
  - `snet-jumphost` — WireGuard VPN gateway VM
- **Network Security Groups** for each subnet
- **Private DNS Zones** for all private endpoints

### Azure Machine Learning
- **Azure ML Workspace** (`mlw-`) with managed virtual network (`AllowInternetOutbound` isolation mode)
- **System and User Assigned Managed Identities** for secure service-to-service communication

### Supporting Services (all with Private Endpoints)
- **Azure Key Vault** (`kv-`) — Secrets and key management
- **Azure Storage Account** (`st`) — Blob and file storage with private endpoints
- **Azure Container Registry** (`acr`) — Premium SKU with private endpoint
- **Log Analytics Workspace** (`log-`) — Centralized logging
- **Application Insights** (`appi-`) — Application performance monitoring

### WireGuard VPN Gateway
- **WireGuard VM** (`vm-wireguard-`) — Ubuntu 24.04 LTS VM running WireGuard on UDP 51820
- **dnsmasq** — DNS forwarder on the VPN gateway (forwards to Azure DNS `168.63.129.16`) so VPN clients can resolve private endpoint DNS
- **Tunnel Subnet** — `10.100.0.0/24` (server `10.100.0.1`, first client `10.100.0.2`)

## Naming Conventions

All resources follow [Azure naming conventions](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations) with the pattern:
```
<abbreviation>-<project>-<environment>-<location>
```

## Azure Verified Modules

This project uses [Azure Verified Modules (AVM)](https://azure.github.io/Azure-Verified-Modules/) for all infrastructure components:

| Module | Version |
|--------|---------|
| [avm-res-network-virtualnetwork](https://registry.terraform.io/modules/Azure/avm-res-network-virtualnetwork/azurerm) | 0.17.1 |
| [avm-res-network-networksecuritygroup](https://registry.terraform.io/modules/Azure/avm-res-network-networksecuritygroup/azurerm) | 0.5.1 |
| [avm-res-machinelearningservices-workspace](https://registry.terraform.io/modules/Azure/avm-res-machinelearningservices-workspace/azurerm) | 0.9.0 |
| [avm-res-keyvault-vault](https://registry.terraform.io/modules/Azure/avm-res-keyvault-vault/azurerm) | 0.10.2 |
| [avm-res-storage-storageaccount](https://registry.terraform.io/modules/Azure/avm-res-storage-storageaccount/azurerm) | 0.6.7 |
| [avm-res-containerregistry-registry](https://registry.terraform.io/modules/Azure/avm-res-containerregistry-registry/azurerm) | 0.5.1 |
| [avm-res-operationalinsights-workspace](https://registry.terraform.io/modules/Azure/avm-res-operationalinsights-workspace/azurerm) | 0.5.1 |
| [avm-res-insights-component](https://registry.terraform.io/modules/Azure/avm-res-insights-component/azurerm) | 0.3.0 |
| [avm-res-compute-virtualmachine](https://registry.terraform.io/modules/Azure/avm-res-compute-virtualmachine/azurerm) | 0.20.0 |
| [avm-res-managedidentity-userassignedidentity](https://registry.terraform.io/modules/Azure/avm-res-managedidentity-userassignedidentity/azurerm) | 0.3.4 |

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.9
- [TFLint](https://github.com/terraform-linters/tflint) for linting
- [WireGuard](https://www.wireguard.com/install/) — install `wg` CLI tools for key generation and a WireGuard client for your OS
- Azure CLI authenticated with sufficient permissions
- An Azure subscription

## Usage

### 1. Generate WireGuard Keys

Each project deploys a WireGuard VPN gateway. You need a **server** key pair and a **client** key pair before running `terraform apply`.

```bash
# Generate server key pair
wg genkey > server.key
wg pubkey < server.key > server.pub

# Generate client key pair
wg genkey > client.key
wg pubkey < client.key > client.pub
```

### 2. Export Terraform Variables

Pass the keys as environment variables so Terraform can configure the VPN gateway:

```bash
export TF_VAR_wireguard_server_private_key=$(cat server.key)
export TF_VAR_wireguard_client_public_key=$(cat client.pub)
```

### 3. Deploy

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### 4. Generate Client VPN Config

After `terraform apply` completes, generate the WireGuard client config using the helper script:

```bash
./generate-wg0-conf.sh client.key server.key
```

This reads Terraform outputs (public IP, VNet CIDR) and produces a `wg0.conf` file. Use it with WireGuard client to connect to newly created environment.

Once connected, you can resolve private DNS zones and reach all private endpoints from your local machine.

## Variables

| Name | Description | Default |
|------|-------------|---------|
| `location` | Azure region for deployment | `eastus` |
| `project` | Project name for resource naming | `aml` |
| `environment` | Environment name (dev, stg, prd) | `dev` |
| `wireguard_server_private_key` | WireGuard server private key (sensitive) | *(required)* |
| `wireguard_client_public_key` | WireGuard client public key | *(required)* |
| `vm_admin_username` | Admin username for WireGuard VM | `azureadmin` |
| `vm_size` | Size of the WireGuard VPN gateway VM | `Standard_D2s_v3` |
| `vm_zone` | Availability zone for the VM | `1` |
| `vnet_address_space` | VNet address space | `["10.0.0.0/16"]` |
| `tags` | Tags to apply to all resources | `{}` |

## Outputs

| Name | Description |
|------|-------------|
| `resource_group_name` | Name of the resource group |
| `vnet_id` | ID of the virtual network |
| `ml_workspace_id` | ID of the Azure ML workspace |
| `key_vault_id` | ID of the Key Vault |
| `storage_account_id` | ID of the Storage Account |
| `container_registry_id` | ID of the Container Registry |
| `wireguard_vm_public_ip` | Public IP of the WireGuard VPN gateway |

<!-- BEGIN_TF_DOCS -->
## TERRAFORM REFERENCES

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | ~> 2.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.5 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azapi"></a> [azapi](#provider\_azapi) | 2.8.0 |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.62.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.8.1 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_app_insights"></a> [app\_insights](#module\_app\_insights) | Azure/avm-res-insights-component/azurerm | 0.3.0 |
| <a name="module_container_registry"></a> [container\_registry](#module\_container\_registry) | Azure/avm-res-containerregistry-registry/azurerm | 0.5.1 |
| <a name="module_identity"></a> [identity](#module\_identity) | Azure/avm-res-managedidentity-userassignedidentity/azurerm | 0.3.4 |
| <a name="module_key_vault"></a> [key\_vault](#module\_key\_vault) | Azure/avm-res-keyvault-vault/azurerm | 0.10.2 |
| <a name="module_log_analytics"></a> [log\_analytics](#module\_log\_analytics) | Azure/avm-res-operationalinsights-workspace/azurerm | 0.5.1 |
| <a name="module_ml_workspace"></a> [ml\_workspace](#module\_ml\_workspace) | Azure/avm-res-machinelearningservices-workspace/azurerm | 0.9.0 |
| <a name="module_nsg_compute"></a> [nsg\_compute](#module\_nsg\_compute) | Azure/avm-res-network-networksecuritygroup/azurerm | 0.5.1 |
| <a name="module_nsg_ml"></a> [nsg\_ml](#module\_nsg\_ml) | Azure/avm-res-network-networksecuritygroup/azurerm | 0.5.1 |
| <a name="module_nsg_pe"></a> [nsg\_pe](#module\_nsg\_pe) | Azure/avm-res-network-networksecuritygroup/azurerm | 0.5.1 |
| <a name="module_nsg_wireguard"></a> [nsg\_wireguard](#module\_nsg\_wireguard) | Azure/avm-res-network-networksecuritygroup/azurerm | 0.5.1 |
| <a name="module_storage_account"></a> [storage\_account](#module\_storage\_account) | Azure/avm-res-storage-storageaccount/azurerm | 0.6.7 |
| <a name="module_vnet"></a> [vnet](#module\_vnet) | Azure/avm-res-network-virtualnetwork/azurerm | 0.17.1 |
| <a name="module_wireguard_vm"></a> [wireguard\_vm](#module\_wireguard\_vm) | Azure/avm-res-compute-virtualmachine/azurerm | 0.20.0 |

## Resources

| Name | Type |
|------|------|
| [azapi_resource.image_builder](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azurerm_private_dns_zone.acr](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone) | resource |
| [azurerm_private_dns_zone.blob](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone) | resource |
| [azurerm_private_dns_zone.file](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone) | resource |
| [azurerm_private_dns_zone.ml_api](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone) | resource |
| [azurerm_private_dns_zone.ml_notebooks](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone) | resource |
| [azurerm_private_dns_zone.vault](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone) | resource |
| [azurerm_private_dns_zone_virtual_network_link.acr](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link) | resource |
| [azurerm_private_dns_zone_virtual_network_link.blob](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link) | resource |
| [azurerm_private_dns_zone_virtual_network_link.file](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link) | resource |
| [azurerm_private_dns_zone_virtual_network_link.ml_api](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link) | resource |
| [azurerm_private_dns_zone_virtual_network_link.ml_notebooks](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link) | resource |
| [azurerm_private_dns_zone_virtual_network_link.vault](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link) | resource |
| [azurerm_resource_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |
| [azurerm_role_assignment.acr_pull_workspace](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.acr_push_workspace](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [random_string.suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |
| [azurerm_public_ip.wireguard](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/public_ip) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_enable_telemetry"></a> [enable\_telemetry](#input\_enable\_telemetry) | Controls whether telemetry is enabled for AVM modules. | `bool` | `true` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | The environment name (e.g. dev, stg, prd) used in resource naming. | `string` | `"dev"` | no |
| <a name="input_location"></a> [location](#input\_location) | The Azure region where the resources will be deployed. | `string` | `"eastus"` | no |
| <a name="input_project"></a> [project](#input\_project) | The project name used in resource naming. | `string` | `"aml"` | no |
| <a name="input_subnet_prefixes"></a> [subnet\_prefixes](#input\_subnet\_prefixes) | The address prefixes for each subnet. The jumphost subnet hosts the WireGuard VPN gateway VM. | <pre>object({<br/>    compute  = string<br/>    jumphost = string<br/>    ml       = string<br/>    pe       = string<br/>  })</pre> | <pre>{<br/>  "compute": "10.0.2.0/24",<br/>  "jumphost": "10.0.5.0/24",<br/>  "ml": "10.0.1.0/24",<br/>  "pe": "10.0.3.0/24"<br/>}</pre> | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources. | `map(string)` | `{}` | no |
| <a name="input_vm_admin_username"></a> [vm\_admin\_username](#input\_vm\_admin\_username) | The admin username for the WireGuard VPN gateway VM. Authentication uses an auto-generated SSH key pair. | `string` | `"azureadmin"` | no |
| <a name="input_vm_size"></a> [vm\_size](#input\_vm\_size) | The size (SKU) of the WireGuard VPN gateway VM. | `string` | `"Standard_D2s_v3"` | no |
| <a name="input_vm_zone"></a> [vm\_zone](#input\_vm\_zone) | The availability zone for the WireGuard VPN gateway VM. Set to null for regions without zone support. | `string` | `"1"` | no |
| <a name="input_vnet_address_space"></a> [vnet\_address\_space](#input\_vnet\_address\_space) | The address space for the virtual network. | `list(string)` | <pre>[<br/>  "10.0.0.0/16"<br/>]</pre> | no |
| <a name="input_wireguard_client_public_key"></a> [wireguard\_client\_public\_key](#input\_wireguard\_client\_public\_key) | WireGuard public key of the first VPN client. Generate with: wg genkey \| wg pubkey | `string` | n/a | yes |
| <a name="input_wireguard_server_private_key"></a> [wireguard\_server\_private\_key](#input\_wireguard\_server\_private\_key) | WireGuard server private key. Generate with: wg genkey | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_application_insights_id"></a> [application\_insights\_id](#output\_application\_insights\_id) | The ID of the Application Insights instance. |
| <a name="output_container_registry_id"></a> [container\_registry\_id](#output\_container\_registry\_id) | The ID of the Container Registry. |
| <a name="output_key_vault_id"></a> [key\_vault\_id](#output\_key\_vault\_id) | The ID of the Key Vault. |
| <a name="output_log_analytics_workspace_id"></a> [log\_analytics\_workspace\_id](#output\_log\_analytics\_workspace\_id) | The ID of the Log Analytics workspace. |
| <a name="output_ml_workspace_id"></a> [ml\_workspace\_id](#output\_ml\_workspace\_id) | The ID of the Azure ML workspace. |
| <a name="output_resource_group_id"></a> [resource\_group\_id](#output\_resource\_group\_id) | The ID of the resource group. |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | The name of the resource group. |
| <a name="output_storage_account_id"></a> [storage\_account\_id](#output\_storage\_account\_id) | The ID of the Storage Account. |
| <a name="output_user_assigned_identity_id"></a> [user\_assigned\_identity\_id](#output\_user\_assigned\_identity\_id) | The ID of the User Assigned Managed Identity. |
| <a name="output_vnet_id"></a> [vnet\_id](#output\_vnet\_id) | The ID of the virtual network. |
| <a name="output_wireguard_admin_ssh_private_key"></a> [wireguard\_admin\_ssh\_private\_key](#output\_wireguard\_admin\_ssh\_private\_key) | Auto-generated SSH private key for the WireGuard VM admin user (stored in Terraform state). |
| <a name="output_wireguard_vm_id"></a> [wireguard\_vm\_id](#output\_wireguard\_vm\_id) | The resource ID of the WireGuard VPN gateway VM. |
| <a name="output_wireguard_vm_public_ip"></a> [wireguard\_vm\_public\_ip](#output\_wireguard\_vm\_public\_ip) | Public IP of the WireGuard VPN gateway. Use as Endpoint in your client wg0.conf. |
<!-- END_TF_DOCS -->
