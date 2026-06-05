# microsoftfoundry-terraform-hostedagent

A fully **network-isolated Microsoft Foundry (AI Foundry v2)** deployment with **hosted agents** and a **private MCP server**. Every backing service runs behind a private endpoint, the AI account is VNet-injected, local auth is disabled wherever supported, and the Application Insights workspace ingests telemetry only over the Azure Monitor Private Link Scope (AMPLS).

The project ships three runnable pieces in addition to the infrastructure:

- **`mcp-server/`** — the multi-auth MCP container that runs in the project's private Container Apps Environment.
- **`hosted-agent-test/`** — a hosted agent (Foundry-managed Container Apps environment) that calls the private MCP server and emits OpenTelemetry traces to App Insights.
- **`private-mcp-test/` / `ampls-test/`** — SDK-level smoke tests for the private MCP path and the AMPLS ingestion path.

---

## Architecture

```
┌────────────────────────── VNet (snet-*, all /24) ───────────────────────────┐
│                                                                              │
│  snet-agent (delegated to Microsoft.App/environments)                       │
│   └── Microsoft-managed CAE for HOSTED AGENTS (networkInjections.scenario)  │
│         ├─ runs container images pulled from the private ACR                │
│         └─ outbound calls reach snet-mcp via the VNet                       │
│                                                                              │
│  snet-mcp (delegated to Microsoft.App/environments)                         │
│   └── User-managed CAE (internal LB only)                                   │
│         └─ mcp-http-server container (FastMCP + multi-auth)                 │
│             image: <acr>/multi-auth-mcp:<tag> (UAMI AcrPull)                │
│                                                                              │
│  snet-pe   AI Services account, ACR, KV, Cosmos, Storage, AI Search,        │
│            AMPLS scoped resources (App Insights + Log Analytics)            │
│                                                                              │
│  snet-wg   WireGuard gateway VM + dnsmasq (developer access)                │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Two Container Apps Environments by design**: Foundry hosted agents run on a Microsoft-managed CAE (created and owned by the Foundry service via `networkInjections.scenario = "agent"`). The MCP server runs on a *separate* user-managed CAE that we own. The hosted agent reaches the MCP server over the shared VNet using its CAE-internal FQDN.

---

## What gets deployed

| Component | Details |
|---|---|
| **AI Services account** | `AIServices` kind (S0), `publicNetworkAccess = Disabled`, `disableLocalAuth = true`, system-assigned MI, `networkInjections.scenario = "agent"` into `snet-agent`, default model deployment `gpt-4o-mini` |
| **AI Foundry project** | System-assigned MI with least-privilege roles for every connected service. Foundry User role assigned by GUID to survive the role-rename rollout |
| **Capability Hosts** | Project-level Agents capability (Cosmos / Storage / AI Search) + account-level capability host auto-provisioned by `networkInjections` |
| **Private MCP server** | `mcp.tf` provisions a UAMI + AcrPull role assignment + an AVM container-app (`Azure/avm-res-app-containerapp/azurerm` v0.9.0) running the image from `mcp-server/`. Internal-LB only |
| **ACR** | Premium SKU, public access disabled, admin disabled, private endpoint |
| **Key Vault (BYO)** | Standard SKU, purge protection on, public access disabled, private endpoint — wired as the first Foundry connection so non-Entra connection secrets land in *your* vault |
| **Storage** | Standard, public access disabled, shared key disabled, blob private endpoint |
| **AI Search** | Standard, public access disabled, local auth disabled, system-assigned MI, private endpoint |
| **Cosmos DB** | Session consistency, local auth disabled, private endpoint. Includes an `azapi_update_resource` workaround for AVM v0.10.0 silently re-enabling local auth (see `data_stores.tf`) |
| **Log Analytics + App Insights** | PerGB2018 / 30-day retention; both attached to **AMPLS** with `ingestion_access_mode = PrivateOnly` |
| **User Container Apps Environment** | Internal-only, VNet-injected into `snet-mcp`, Consumption profile, Log Analytics integrated — hosts the private MCP server |
| **WireGuard VPN** | Lightweight Ubuntu 24.04 + WireGuard + dnsmasq; developer access to every private endpoint |
| **APIM (optional)** | PremiumV2, VNet-injected. Enable with `enable_apim = true` |

See `variables.tf` for every input. Defaults target `swedencentral` (verified reliable for Foundry `networkInjections` and AI Search) and workload `privateagent` / environment `dev`.

---

## Prerequisites

- Terraform >= 1.9
- Azure CLI, logged in (`az login`) against a subscription that allows AI Services, AVM modules, and Azure Monitor Private Link Scope
- WireGuard tools (`wg`) — for VPN key generation
- Docker (with `buildx`) — to build the MCP and hosted-agent images for `linux/amd64`
- Python 3.11+ + [uv](https://docs.astral.sh/uv/) — to run the test harnesses

---

## Deploy

### 1. Generate WireGuard keys

```bash
wg genkey > server.key && wg pubkey < server.key > server.pub
wg genkey > client.key && wg pubkey < client.key > client.pub

export TF_VAR_wireguard_server_private_key=$(cat server.key)
export TF_VAR_wireguard_client_public_key=$(cat client.pub)
```

### 2. Apply the infrastructure

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

This creates everything *including* the MCP container app — but on the very first apply the container app will fail to start because the image tag (`multi-auth-mcp:latest`) doesn't exist in the ACR yet. That's fine; build and push it next.

### 3. Build and push the MCP image

```bash
cd mcp-server/
ACR_NAME=$(cd .. && terraform output -raw acr_login_server | cut -d. -f1) ./build_and_push.sh
```

The script does `az acr login` then `docker buildx build --platform linux/amd64 --push`. Default tag is `latest`; override with `IMAGE_TAG=v1 ./build_and_push.sh` and then `terraform apply -var mcp_image_tag=v1` to roll a new revision.

### 4. Generate a WireGuard client config and connect

```bash
./generate-wg0-conf.sh client.key server.key
# Import wg0.conf into your WireGuard client and connect
```

### 5. Build and register the hosted agent

```bash
cd hosted-agent-test/
ACR_NAME=$(cd .. && terraform output -raw acr_login_server | cut -d. -f1) ./build_and_push.sh
PROJECT_ENDPOINT=$(cd .. && terraform output -raw ai_account_endpoint)api/projects/$(cd .. && terraform output -raw ai_project_name)
MCP_URL=$(cd .. && terraform output -raw mcp_server_url)
PROJECT_ENDPOINT=$PROJECT_ENDPOINT MCP_URL=$MCP_URL uv run create_hosted_agent.py
PROJECT_ENDPOINT=$PROJECT_ENDPOINT uv run manage_hosted_agent.py start
PROJECT_ENDPOINT=$PROJECT_ENDPOINT uv run invoke_hosted_agent.py "What is 17 + 25?"
```

You must be on WireGuard for steps that hit `PROJECT_ENDPOINT` — the AI Services account is private.

---

## Outputs to know

| Output | What it's for |
|---|---|
| `ai_account_endpoint`, `ai_project_name` | Build `PROJECT_ENDPOINT` for SDK / hosted-agent calls |
| `acr_login_server` | First half of every image reference; feed to `build_and_push.sh` |
| `mcp_server_url` | `https://<fqdn>/noauth/mcp` — the URL the hosted agent uses as its `MCPStreamableHTTPTool` |
| `mcp_server_fqdn` | The CAE-internal FQDN of the MCP container app, useful for `curl` from WireGuard |
| `mcp_uami_client_id` | Client ID of the UAMI that pulls the MCP image from ACR |
| `container_apps_env_default_domain` | The `*.<random>.swedencentral.azurecontainerapps.io` zone — the auto-provisioned private DNS zone lives here |
| `wireguard_vm_public_ip`, `wireguard_admin_ssh_private_key` | VPN gateway access |

---

## Known caveats and pre-existing drift

These are real and surface in `terraform plan` output. They are **not** caused by the MCP work — confirm a plan diff before assuming anything is broken.

| Resource | Behavior | Mitigation |
|---|---|---|
| `module.cosmos.azurerm_cosmosdb_account.this` | AVM `Azure/avm-res-documentdb-databaseaccount/azurerm` v0.10.0 flips `local_authentication_disabled` to `false` when `sql_databases` is empty | `azapi_update_resource` in `data_stores.tf` re-asserts `disableLocalAuth = true` after every apply. Fixed upstream on `main` (commit `3c6139c`) but unreleased |
| `module.wireguard_vm.azurerm_linux_virtual_machine.this[0]` | `os_disk.storage_account_type` drift between config (`Premium_LRS`) and Azure (`Standard_LRS`) **forces replacement** | Do *not* run a blind full `terraform apply` — it will destroy and recreate the VPN gateway. Use targeted applies or reconcile the disk type first |
| `module.acr` / `module.storage` | Storage data scanner `private_link_access` block read-back drift | Cosmetic; Azure re-populates this on read |
| `azapi_resource.ai_account` | `disableLocalAuth` body drift | The `azapi_update_resource` block keeps this set; cosmetic in plan |
| `module.mcp_container_app.azapi_resource.container_app` | After an in-place template update, plan shows `latestRevisionName` / `latestRevisionFqdn` changing | Purely the AVM output read-back; Azure-side revision rename, not a config diff. Resolves on next refresh |

---

## File layout

```
microsoftfoundry-terraform-hostedagent/
├── *.tf                          # Terraform root module (one file per concern)
├── variables.tf                  # All inputs incl. var.mcp_image_tag
├── outputs.tf                    # MCP server URL / FQDN / UAMI client ID exposed
│
├── mcp-server/                   # Private MCP container source (formerly Docker Hub)
│   ├── Dockerfile                # Pinned python:3.11.14-slim-trixie
│   ├── requirements.txt          # Pinned (37 deps, captured from running image)
│   ├── build_and_push.sh         # az acr login + buildx --push --platform linux/amd64
│   ├── src/                      # FastMCP server (config, logging, prm, server_multi_auth)
│   └── README.md
│
├── hosted-agent-test/            # Foundry hosted-agent integration test
│   ├── agent-app/                # Agent Python (uses MCPStreamableHTTPTool)
│   ├── build_and_push.sh
│   ├── create_hosted_agent.py
│   ├── manage_hosted_agent.py
│   ├── invoke_hosted_agent.py
│   └── README.md
│
├── private-mcp-test/             # SDK smoke test (azure-ai-projects)
└── ampls-test/                   # AMPLS Phase E rollout REST probe
```

---

## See also

- Parent project README: [`../README.md`](../README.md)
- AVM container app module: [Azure/avm-res-app-containerapp/azurerm v0.9.0](https://registry.terraform.io/modules/Azure/avm-res-app-containerapp/azurerm/0.9.0)
- Foundry hosted-agent docs: [Microsoft Foundry samples](https://github.com/microsoft-foundry/foundry-samples)
