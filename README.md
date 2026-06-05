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

### [`pytorchlab-terraform/`](pytorchlab-terraform/)

A simple GPU VM for PyTorch development and Jupyter Notebook — no complex networking, just a VNet + NSG + public IP. Designed for remote ML experimentation from VS Code.

**Key Components:**

| Component | Details |
|---|---|
| **GPU VM** | `Standard_NC4as_T4_v3` — NVIDIA T4 (16 GB VRAM), Ubuntu 24.04 LTS, SSH key auth, system-assigned managed identity |
| **Software** | CUDA drivers (Azure VM extension), Miniconda, PyTorch (CUDA 12.4), JupyterLab — all installed via cloud-init |
| **Temp Disk** | 176 GB local NVMe SSD configured for fast PyTorch I/O (`TORCH_HOME`, `TMPDIR`, data/checkpoints symlinks) |
| **Networking** | Single VNet + subnet, NSG restricts SSH (port 22) to a configurable source IP |
| **Access** | VS Code Remote-SSH + Jupyter extension — no ports exposed beyond SSH |

See [pytorchlab-terraform/README.md](pytorchlab-terraform/README.md) for full details.

---

### [`microsoftfoundry-terraform-hostedagent/`](microsoftfoundry-terraform-hostedagent/)

A network-isolated **Microsoft Foundry (AI Foundry)** deployment ready to run **hosted agents** — AI Services account, Foundry project, account- + project-level Capability Hosts, container registry, Key Vault (Bring-Your-Own), and Azure Monitor Private Link Scope — all locked behind private endpoints with public access disabled and local auth turned off across every backing service. The AI account uses VNet-injected agent networking, and a private Container Apps Environment is wired into the MCP subnet for custom tool servers. Default region: `swedencentral`.

**Key Components:**

| Component | Details |
|---|---|
| **AI Services Account** | `AIServices` kind (S0 SKU), public network access disabled, local auth disabled, system-assigned managed identity, VNet network injection for the agent subnet, model deployment (default: `gpt-4o-mini`) |
| **AI Foundry Project** | System-assigned identity with least-privilege role assignments for all connected services (Foundry User role assigned by GUID to survive the Foundry role-rename rollout) |
| **Capability Hosts** | Project-level Agents capability (Cosmos DB threads / Storage blob / AI Search vector store) + an account-level capability host auto-provisioned by `networkInjections.scenario = "agent"` for hosted agents |
| **Azure Container Registry** | Premium SKU, public access disabled, admin disabled, private endpoint — hosts hosted-agent container images |
| **Key Vault (BYO)** | Standard SKU, purge protection on, public access disabled, private endpoint — wired as the first Foundry connection so all non-Entra connection secrets are stored in **your** vault instead of Microsoft-managed KV |
| **Storage Account** | Standard ZRS/GRS, public access disabled, shared key disabled, private endpoint for blob |
| **AI Search** | Standard SKU, public access disabled, local auth disabled, system-assigned managed identity, private endpoint |
| **Cosmos DB** | Session consistency, local auth disabled, private endpoint (SQL API) — includes an `azapi_update_resource` workaround for AVM v0.10.0 silently re-enabling local auth |
| **Log Analytics + Application Insights** | PerGB2018 / 30-day retention; both attached to an **Azure Monitor Private Link Scope (AMPLS)** with phase-controlled `ingestion_access_mode` / `query_access_mode` (default `PrivateOnly`) |
| **Container Apps Environment** | Internal-only (no public ingress), VNet-injected into the MCP subnet, Consumption workload profile, integrated with Log Analytics |
| **Virtual Network** | Dedicated subnets for agents (delegated to `Microsoft.App/environments`), private endpoints, APIM (optional), MCP (Container Apps), and WireGuard VPN |
| **API Management** | Optional PremiumV2 APIM, VNet-injected (enabled via `enable_apim` variable) |
| **Private DNS Zones** | Zones for AI Services, OpenAI, Cognitive Services, AI Search, Blob Storage, Cosmos DB, ACR, Key Vault, and the five AMPLS zones (`monitor`, `oms`, `ods`, `agentsvc`, blob — reused) |
| **WireGuard VPN** | Same pattern as other projects — a WireGuard gateway VM with dnsmasq for developer access to private endpoints |

**Companion test harnesses and code projects:**

- [`mcp-server/`](microsoftfoundry-terraform-hostedagent/mcp-server/) — source for the multi-auth MCP container that runs in the private Container Apps Environment. Includes a pinned `Dockerfile`, a `build_and_push.sh` script targeting the private ACR, and the FastMCP Python server (`add`, `time` tools + an OAuth-protected resource metadata endpoint). The container app itself is provisioned by `mcp.tf` via the AVM container-app module.
- [`hosted-agent-test/`](microsoftfoundry-terraform-hostedagent/hosted-agent-test/) — end-to-end workflow for building a hosted-agent container image, pushing to the private ACR, registering a hosted agent version that consumes the private MCP server, and invoking it via the Responses API with App Insights tracing.
- [`ampls-test/`](microsoftfoundry-terraform-hostedagent/ampls-test/) — REST-level probe that proves the App Insights private ingestion path end-to-end (validates AMPLS Phase E-1 → E-2 → E-3 rollout from inside and outside the VNet).
- [`private-mcp-test/`](microsoftfoundry-terraform-hostedagent/private-mcp-test/) — SDK tests for agents calling AI Search and private MCP servers over the Data Proxy.

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.9
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (authenticated via `az login`)
- [WireGuard tools](https://www.wireguard.com/install/) (`wg` command) — for VPN key generation and client config
- An Azure subscription with sufficient permissions

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
cd <project-folder>/
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
