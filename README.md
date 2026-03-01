# azure-IaC-avm

Azure Infrastructure as Code built entirely with [Azure Verified Modules (AVM)](https://azure.github.io/Azure-Verified-Modules/) and Terraform. Every deployment is designed around **private networking** — services communicate over private endpoints, clusters run as private clusters, and public access is disabled wherever possible.

## Projects

### [`aks-terraform/`](aks-terraform/)

A fully private AKS environment where the Kubernetes API server is only reachable through a private endpoint, all egress traffic is forced through Azure Firewall, and container images are pulled from a private ACR over a private endpoint — nothing is exposed to the public internet. Based on the [sg-aks-workshop](https://github.com/eggboy/sg-aks-workshop) reference architecture.

**Key Components:**

| Component | Details |
|---|---|
| **AKS Private Cluster** | API server accessible only via private endpoint, Azure CNI Overlay + Cilium dataplane, user-defined routing through Azure Firewall, Entra ID + Azure RBAC, OIDC/workload identity, Key Vault Secrets Provider, Azure Policy, Container Insights |
| **Virtual Network** | `100.64.0.0/16` with dedicated subnets for AKS nodes, internal load balancers, App Gateway, Azure Firewall, WireGuard VPN, and private endpoints |
| **Azure Firewall** | Standard SKU, zone-redundant (1/2/3), with comprehensive egress rules covering AKS core requirements, Azure Monitor, GPU workloads, Defender, Azure Policy, and Cluster Extensions |
| **Azure Container Registry** | Premium SKU, public access disabled, accessible only through a private endpoint in the VNet |
| **Log Analytics** | Centralized logging — AKS, Firewall, and ACR all send diagnostic data here |
| **WireGuard VPN** | A lightweight Ubuntu 24.04 VM running WireGuard + dnsmasq, enabling developers to reach the private API server and resolve private DNS zones from their local machines |

---

### [`azuremachinelearning-terraform/`](azuremachinelearning-terraform/)

A network-isolated Azure Machine Learning workspace where every supporting service — Key Vault, Storage, Container Registry — is locked behind private endpoints. The ML workspace itself uses managed VNet isolation (`AllowInternetOutbound` mode), so compute instances and clusters never sit on a public network.

**Key Components:**

| Component | Details |
|---|---|
| **Azure ML Workspace** | Managed VNet isolation with system + user-assigned managed identities |
| **Virtual Network** | Dedicated subnets for ML serverless compute, private endpoints, and a VPN jumphost |
| **Key Vault** | Secrets and key management, accessible only via private endpoint |
| **Storage Account** | Blob and file storage, both exposed exclusively through private endpoints |
| **Container Registry** | Premium SKU, reachable only through a private endpoint |
| **Application Insights** | Performance monitoring backed by Log Analytics |
| **WireGuard VPN** | Same pattern as AKS — a WireGuard gateway VM with dnsmasq so developers can resolve and reach all private endpoints from outside the VNet |

See [azuremachinelearning-terraform/README.md](azuremachinelearning-terraform/README.md) for full details.

---

### [`microsoftfoundry-terraform/`](microsoftfoundry-terraform/)

Scaffolding for a **Microsoft Foundry** deployment. Currently contains provider configuration (`azurerm ~> 4.0`, `azapi ~> 2.0`) — work in progress.

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.9
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (authenticated via `az login`)
- An Azure subscription with sufficient permissions

## Usage

```bash
cd <project-folder>/
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```
