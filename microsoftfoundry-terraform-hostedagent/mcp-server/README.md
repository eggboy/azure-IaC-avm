# multi-auth MCP server

A Streamable-HTTP Model Context Protocol (MCP) server that supports three
authentication modes side-by-side on the same listener:

| Path                | Auth                                                       |
| ------------------- | ---------------------------------------------------------- |
| `/noauth/mcp`       | None — origin allow-list only (`ALLOWED_ORIGINS`)          |
| `/mcp`              | API key (`Authorization: Bearer <key>`) **or** Entra JWT   |
| `/healthz`          | Open (liveness probe)                                      |
| `/authz`            | Reflects the calling request's auth context (debug helper) |
| `/.well-known/oauth-protected-resource[/mcp]` | OAuth Protected Resource Metadata document |

The hosted agent in this repository (see [`../hosted-agent-test/`](../hosted-agent-test/))
calls the **`/noauth/mcp`** endpoint over the project's private VNet.

## Provenance

This source is the unmodified contents of `/app/` extracted from
`docker.io/eggboy/multi-auth-mcp@sha256:b672376c25c163bdbc629f0dccccbf1e9ae160452743e8a5cc1abe222833c951`
(the image originally pushed by the project owner on 2026-03-16). Identical
SHA-1 verified for all four Python source files. `requirements.txt` is the
`pip freeze` output of the running container, pinning the transitive closure
the image was tested against. The Dockerfile is reconstructed from
`docker history` of the same image.

## Architecture (within this project)

```
                                 ┌──────────────────────────────────────┐
                                 │ Microsoft-managed CAE (legionservicelink)
                                 │ snet-agent · injected via networkInjections
                                 │  ┌──────────────────────────────────┐│
                                 │  │ hosted agent (../hosted-agent-test) ││
                                 │  └────────────┬─────────────────────┘│
                                 └───────────────┼──────────────────────┘
                                                 │ HTTPS
                                                 │ via auto-private-DNS
                                                 ▼
┌───────────────────────────────────────────────────────────────────────┐
│ user-managed CAE  (cae-privateagent-dev-d0bl)                         │
│ snet-mcp · internal ingress only                                      │
│ ┌───────────────────────────────────────────────────────────────────┐ │
│ │ Container App: mcp-http-server (this image)                       │ │
│ │   uvicorn src.server_multi_auth:app --host 0.0.0.0 --port 8080    │ │
│ │   Endpoints: /noauth/mcp  /mcp  /healthz  /authz  /.well-known/.. │ │
│ └───────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────┘
```

## Tools / resources / prompts exposed

| Kind     | Name                       | Notes                                                                                   |
| -------- | -------------------------- | --------------------------------------------------------------------------------------- |
| tool     | `get_access_flow`          | Returns which auth mode the caller used (NoAuth / ApiKey / EntraID variants).           |
| tool     | `add(a, b)`                | Trivial demo tool — the hosted-agent integration test calls this.                       |
| tool     | `whoami`                   | Hint that `/authz` is the introspection endpoint.                                       |
| tool     | `long_running_operation`   | Reports progress via MCP notifications; used to exercise streaming.                     |
| resource | `greeting://{name}`        | Returns `"Hello, {name}!"`.                                                             |
| prompt   | `greet_template`           | Generates a `"Write a {style} greeting for {name}."` prompt.                            |

## File layout

```
mcp-server/
├── Dockerfile               # python:3.11.14-slim-trixie, reconstructed from image history
├── requirements.txt         # pinned (pip freeze of the running image)
├── build_and_push.sh        # docker buildx --platform linux/amd64 --push to ACR
├── .dockerignore
├── .env.example             # documents every env var src/config.py reads
└── src/
    ├── config.py            # env-driven configuration (see Configuration below)
    ├── logging_config.py    # stdout structured logging
    ├── prm.py               # OAuth Protected Resource Metadata response builder
    └── server_multi_auth.py # Starlette app + FastMCP mount + auth middleware
```

## Configuration

All settings come from environment variables. See [`.env.example`](.env.example)
for the canonical list with descriptions. The most relevant ones:

| Variable               | Default                                                                                | Purpose                                                                            |
| ---------------------- | -------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `PORT`                 | `8080`                                                                                 | Listener port (matches Dockerfile `EXPOSE`).                                       |
| `LOG_LEVEL`            | `INFO`                                                                                 |                                                                                    |
| `API_KEYS`             | `devkey123`                                                                            | Comma-separated bearer tokens accepted on `/mcp`. Override or set empty in prod.   |
| `ALLOWED_ORIGINS`      | `http://localhost:6274,http://localhost:5173,https://ai.azure.com`                     | Origin header allow-list (also enforced on `/noauth/mcp`).                         |
| `TENANT_ID`            | (Microsoft public tenant placeholder)                                                  | JWKS / issuer for Entra JWT validation. Set to your own tenant in prod.            |
| `MCP_APP_ID`           | (sample app placeholder)                                                               | Required `aud` claim on validated JWTs.                                            |
| `REQUIRED_SCOPES`      | _empty_                                                                                | Space-separated scopes that must ALL be present.                                   |
| `REQUIRED_ROLES`       | _empty_                                                                                | Space-separated app roles that must ALL be present.                                |
| `ALLOWED_AGENT_IDS`    | _empty_                                                                                | Client IDs classified as `agent_identity` subtype in `/authz` and `get_access_flow`. |
| `ALLOWED_PROJECT_MIS`  | _empty_                                                                                | Client IDs classified as `project_managed_identity` subtype.                       |

### Security boundaries

Two things are worth being explicit about:

1. **`/noauth/mcp` is unauthenticated.** Anything with a network path into
   the container app's VNet (WireGuard clients, APIM, future workloads, a
   compromised neighbour) can call it. The trust boundary is the VNet, not
   the application. If that boundary ever loosens, switch the hosted agent
   to `/mcp` and provision an API key or an Entra app registration.
2. **`API_KEYS` defaults to `devkey123`** — a placeholder. Override it for
   any deployment you care about, ideally via a Container App secret rather
   than a plain env var.

## Local development

```bash
python3.11 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # then edit
uvicorn src.server_multi_auth:app --host 0.0.0.0 --port 8080 --reload
curl http://localhost:8080/healthz
```

## Build and push to ACR

```bash
export ACR_NAME=crprivateagentdevd0bl    # no .azurecr.io suffix
export IMAGE_TAG=v1                       # immutable tags recommended; defaults to "latest"
./build_and_push.sh
```

The script does an `az acr login` and a `docker buildx build --platform linux/amd64 --push`,
so the architecture is always correct regardless of your laptop's CPU.

## Deploy / update the container app

The container app `mcp-http-server` and its UAMI are managed by the Terraform
in this project's parent directory (`../mcp.tf`). After pushing a new image:

```bash
# Roll the existing app onto the new image (no infra change)
az containerapp update -n mcp-http-server -g rg-privateagent-dev-swedencentral \
  --image crprivateagentdevd0bl.azurecr.io/multi-auth-mcp:v1
```

Or, if you set `var.mcp_image_tag = "v1"` and re-apply Terraform, the change
flows through the AVM container-app module automatically.

## End-to-end test

From a WireGuard-connected machine (so you have a route into the VNet):

```bash
# Health
curl https://mcp-http-server.prouddesert-5ff69fd5.swedencentral.azurecontainerapps.io/healthz

# Reflect auth context (anonymous via /noauth/mcp prefix)
curl https://mcp-http-server.prouddesert-5ff69fd5.swedencentral.azurecontainerapps.io/authz
```

To exercise it end-to-end through the hosted agent:

```bash
cd ../hosted-agent-test
uv run invoke_hosted_agent.py "What is 17+25?"
```
