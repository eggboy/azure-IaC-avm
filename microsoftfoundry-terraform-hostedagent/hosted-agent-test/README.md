# Hosted Agent Test

End-to-end workflow for building, deploying, and invoking a **hosted agent** on Microsoft Foundry Agent Service.

> **Reference:** <https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents>

---

## Prerequisites

| Requirement | Notes |
|---|---|
| Terraform infrastructure deployed | The parent Terraform config provisions ACR, account-level capability host, and RBAC |
| Azure CLI | `az` with `cognitiveservices` extension |
| Docker | For building the container image (`--platform linux/amd64` required) |
| Python 3.10+ | Scripts use [uv](https://github.com/astral-sh/uv) inline deps |
| `azure-ai-projects >= 2.0.0` | Installed automatically by `uv run` |

---

## Folder Structure

```
hosted-agent-test/
├── README.md                   # This file
├── build_and_push.sh           # Build Docker image and push to ACR
├── create_hosted_agent.py      # Register hosted agent version (azure-ai-projects SDK)
├── invoke_hosted_agent.py      # Invoke deployed agent via Responses API
├── manage_hosted_agent.py      # Start / stop / list / delete agent (az CLI)
└── agent-app/
    ├── main.py                 # Agent code (Agent Framework + hosting adapter)
    ├── requirements.txt        # Python deps for the container
    └── Dockerfile              # Container image definition
```

---

## Quick Start

### 1. Set environment variables

```bash
# From Terraform outputs
export ACR_NAME="$(terraform -chdir=.. output -raw acr_login_server | cut -d. -f1)"
export PROJECT_ENDPOINT="$(terraform -chdir=.. output -raw ai_account_endpoint)/api/projects/$(terraform -chdir=.. output -raw ai_project_name)"
export AGENT_NAME="my-hosted-agent"
export MODEL_NAME="gpt-4o-mini"
```

### 2. Build and push the container image

```bash
chmod +x build_and_push.sh
./build_and_push.sh
```

> **Important:** The build script uses `--platform linux/amd64`. Hosted agents run on Linux AMD64 — ARM64 images (Apple Silicon) will fail.

### 3. Create the hosted agent version

```bash
export ACR_IMAGE="${ACR_NAME}.azurecr.io/hosted-agent:v1"
uv run create_hosted_agent.py
```

### 4. Start the agent deployment

```bash
uv run manage_hosted_agent.py start --version 1 --min-replicas 0 --max-replicas 2
```

> `--min-replicas 0` enables scale-to-zero (no cost when idle, but cold start on first request).

### 5. Invoke the agent

```bash
uv run invoke_hosted_agent.py
```

### 6. Stop / clean up

```bash
# Stop (sets replicas to 0)
uv run manage_hosted_agent.py stop --version 1

# Or delete entirely
uv run manage_hosted_agent.py delete --version 1
```

---

## Local Testing

You can test the agent locally before deploying to Foundry:

```bash
cd agent-app

# Set env vars for local run
export AZURE_AI_PROJECT_ENDPOINT="<your-project-endpoint>"
export MODEL_DEPLOYMENT_NAME="gpt-4o-mini"

pip install -r requirements.txt
python main.py
```

The hosting adapter starts a server on `http://localhost:8088`. Test with:

```bash
curl -X POST http://localhost:8088/responses \
  -H "Content-Type: application/json" \
  -d '{"input": "What time is it in Seattle?"}'
```

---

## How It Works

### Account-Level Capability Host

Hosted agents require an **account-level** capability host (in addition to the project-level one used by prompt agents):

```
Microsoft.CognitiveServices/accounts/<account>/capabilityHosts/accountcaphost
```

This is configured in Terraform with `enablePublicHostingEnvironment: true`.

### Agent Identity

- **Before publishing:** the agent runs with the **project managed identity**
- **After publishing:** Foundry provisions a **dedicated agent identity** — you must reconfigure any resource permissions

### Container Requirements

- Must expose port `8088`
- Must be built for `linux/amd64` architecture
- Uses the `azure-ai-agentserver-*` hosting adapter packages
