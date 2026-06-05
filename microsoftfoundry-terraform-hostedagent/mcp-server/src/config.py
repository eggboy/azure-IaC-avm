import os
import sys

from dotenv import load_dotenv

load_dotenv()

TENANT_ID = os.getenv("TENANT_ID", "72f988bf-86f1-41af-91ab-2d7cd011db47")
RESOURCE_ID = os.getenv("RESOURCE_ID", "api://multi-auth-mcp")

MCP_AUDIENCE = os.getenv("MCP_AUDIENCE", "api://multi-auth-mcp/.default")
MCP_APP_ID = os.getenv("MCP_APP_ID", "ae9a5057-04c6-4c7d-b9e7-85189467f69b")

AUTH_SERVER_URL = f"https://login.microsoftonline.com/{TENANT_ID}/v2.0" if TENANT_ID else None

app_name = os.environ.get("CONTAINER_APP_NAME", None)
dns_suffix = os.environ.get("CONTAINER_APP_ENV_DNS_SUFFIX", None)
RESOURCE_URL = f"https://{app_name}.{dns_suffix}/mcp" if app_name and dns_suffix else None

API_KEYS = set(filter(None, [s.strip() for s in os.getenv("API_KEYS", "devkey123").split(",")]))

ALLOWED_ORIGINS = set(
    filter(
        None,
        [
            s.strip()
            for s in os.getenv(
                "ALLOWED_ORIGINS",
                "http://localhost:6274,http://localhost:5173,https://ai.azure.com",
            ).split(",")
        ],
    )
)
PORT = int(os.getenv("PORT", "8080"))

OIDC_DISCOVERY = (
    f"https://login.microsoftonline.com/{TENANT_ID}/v2.0/.well-known/openid-configuration" if TENANT_ID else None
)

PRM_PATH = "/.well-known/oauth-protected-resource"

PUBLIC_PATHS = {
    "/healthz",
    PRM_PATH,
}

# Configuration for Auth
REQUIRED_SCOPES = set(os.getenv("REQUIRED_SCOPES", "").split()) if os.getenv("REQUIRED_SCOPES") else set()
REQUIRED_ROLES = set(os.getenv("REQUIRED_ROLES", "").split()) if os.getenv("REQUIRED_ROLES") else set()
ALLOWED_AGENT_IDS = set(filter(None, [s.strip() for s in os.getenv("ALLOWED_AGENT_IDS", "").split(",")]))
ALLOWED_PROJECT_MIS = set(filter(None, [s.strip() for s in os.getenv("ALLOWED_PROJECT_MIS", "").split(",")]))

JWKS_URL = f"https://login.microsoftonline.com/{TENANT_ID}/discovery/v2.0/keys" if TENANT_ID else ""

# Path-based no-auth prefix (explicit override)
PUBLIC_MCP_PREFIX = "/noauth/mcp"
AUTH_MCP_PREFIX = "/mcp"

# Log configuration to stdout (before logging is fully initialized)
print("--- [CONFIG] Loaded Configuration ---", file=sys.stdout)
print(f"TENANT_ID: {TENANT_ID}", file=sys.stdout)
print(f"RESOURCE_ID: {RESOURCE_ID}", file=sys.stdout)
print(f"MCP_APP_ID: {MCP_APP_ID}", file=sys.stdout)
print(f"AUTH_SERVER_URL: {AUTH_SERVER_URL}", file=sys.stdout)
print(f"RESOURCE_URL: {RESOURCE_URL}", file=sys.stdout)
print(f"API_KEYS provided: {'Yes' if API_KEYS else 'No'} (count: {len(API_KEYS)})", file=sys.stdout)
print(f"ALLOWED_ORIGINS: {ALLOWED_ORIGINS}", file=sys.stdout)
print(f"PORT: {PORT}", file=sys.stdout)
print(f"REQUIRED_SCOPES: {REQUIRED_SCOPES}", file=sys.stdout)
print(f"REQUIRED_ROLES: {REQUIRED_ROLES}", file=sys.stdout)
print(f"ALLOWED_AGENT_IDS: {ALLOWED_AGENT_IDS}", file=sys.stdout)
print(f"ALLOWED_PROJECT_MIS: {ALLOWED_PROJECT_MIS}", file=sys.stdout)
print("-------------------------------------", file=sys.stdout, flush=True)
