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

### [`aro-terraform/`](aro-terraform/)

A fully private Azure Red Hat OpenShift (ARO) cluster where both the API server and ingress are set to **Private** visibility — nothing is exposed to the public internet. The cluster uses managed identities with platform workload identity federation (no service principal), and all egress is routed through a NAT Gateway with a static public IP.

**Key Components:**

| Component | Details |
|---|---|
| **ARO Private Cluster** | OpenShift 4.16, API server + Ingress set to Private visibility, managed identities with platform workload identity federation for operator components (cloud-controller-manager, disk/file CSI drivers, image-registry, ingress, machine-api) |
| **Virtual Network** | Dedicated subnets for master nodes, worker nodes, private endpoints, and WireGuard VPN — master/worker subnets include service endpoints for Storage and Container Registry |
| **NAT Gateway** | Static outbound public IP for cluster egress, attached to master and worker subnets (replaces default outbound access) |
| **Managed Identities** | Cluster-level user-assigned identity + per-operator platform workload identities with federated credentials and least-privilege network role assignments |
| **Log Analytics** | Private ingestion/query disabled for full lockdown, with private DNS zones for ODS, OMS, and Monitor endpoints |
| **Private DNS Zones** | `privatelink.<region>.aroapp.io` for API server resolution, plus Log Analytics private link zones |
| **WireGuard VPN** | Same pattern as AKS — a WireGuard gateway VM with dnsmasq so developers can resolve and reach all private endpoints from outside the VNet |

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

A network-isolated **Microsoft Foundry (AI Foundry)** deployment with an AI Services account, Foundry project, and Capability Host for Agents — all locked behind private endpoints with public access disabled. The AI account uses VNet-injected network injection for the agent subnet, and every backing service (Storage, AI Search, Cosmos DB) is reachable only through private endpoints.

**Key Components:**

| Component | Details |
|---|---|
| **AI Services Account** | `AIServices` kind (S0 SKU), public network access disabled, system-assigned managed identity, VNet network injection for the agent subnet, model deployments (e.g. gpt-4o-mini) |
| **AI Foundry Project** | System-assigned identity with least-privilege role assignments for all connected services |
| **Capability Host** | Agents capability with connections to Cosmos DB (thread storage), Storage (blob), and AI Search (vector store) |
| **Storage Account** | Standard ZRS/GRS, public access disabled, shared key disabled, private endpoint for blob |
| **AI Search** | Standard SKU, public access disabled, local auth disabled, system-assigned managed identity, private endpoint |
| **Cosmos DB** | Session consistency, local auth disabled, private endpoint (SQL API) |
| **Log Analytics** | PerGB2018 SKU, 30-day retention, public ingestion and query disabled for full network lockdown |
| **Container Apps Environment** | Internal-only (no public ingress), VNet-injected into the MCP subnet, Consumption workload profile, integrated with Log Analytics |
| **Virtual Network** | Dedicated subnets for agents, private endpoints, APIM (optional), MCP (Container Apps), and WireGuard VPN |
| **API Management** | Optional PremiumV2 APIM, VNet-injected (enabled via `enable_apim` variable) |
| **Private DNS Zones** | Zones for AI Services, OpenAI, Cognitive Services, Blob Storage, AI Search, and Cosmos DB |
| **WireGuard VPN** | Same pattern as other projects — a WireGuard gateway VM with dnsmasq for developer access to private endpoints |

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
