# src/server_multi_auth.py
import asyncio
import contextlib
import contextvars

import jwt
from jwt import InvalidTokenError, PyJWKClient
from mcp.server.fastmcp import Context, FastMCP
from mcp.server.transport_security import TransportSecuritySettings
from starlette.applications import Starlette
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.middleware.cors import CORSMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, PlainTextResponse, Response
from starlette.routing import Mount, Route

from .config import (
    ALLOWED_AGENT_IDS,
    ALLOWED_ORIGINS,
    ALLOWED_PROJECT_MIS,
    API_KEYS,
    AUTH_MCP_PREFIX,
    AUTH_SERVER_URL,
    JWKS_URL,
    MCP_APP_ID,
    PORT,
    PRM_PATH,
    PUBLIC_MCP_PREFIX,
    PUBLIC_PATHS,
    REQUIRED_ROLES,
    REQUIRED_SCOPES,
)
from .logging_config import get_logger, setup_logging
from .prm import build_prm

setup_logging()
logger = get_logger("server_multi_auth")
logger.info("Logging initialized")

auth_ctx = contextvars.ContextVar("auth_ctx", default={})

# -----------------------------
# Helpers
# -----------------------------


def _unauthorized(error: str, desc: str, request: Request) -> Response:
    headers = {
        "WWW-Authenticate": f'Bearer realm="mcp", resource_metadata="{request.url.scheme}://{request.url.netloc}{PRM_PATH}"'
    }
    logger.info(f"rquested path: {request.url.path}, adding WWW-Authenticate header: {headers}")
    return JSONResponse({"error": error, "error_description": desc}, status_code=401, headers=headers)


def _forbidden(error: str, desc: str) -> Response:
    return JSONResponse({"error": error, "error_description": desc}, status_code=403)


# -----------------------------
# Middleware (multi-auth + path-based no-auth)
# -----------------------------
class MultiAuthMiddleware(BaseHTTPMiddleware):
    def __init__(self, app):
        super().__init__(app)
        self.jwks_client = PyJWKClient(JWKS_URL) if JWKS_URL else None

    async def _run_with_auth(self, request: Request, auth_data: dict, call_next):
        request.state.auth = auth_data
        token = auth_ctx.set(auth_data)
        try:
            return await call_next(request)
        finally:
            auth_ctx.reset(token)

    async def dispatch(self, request: Request, call_next):
        logger.info(f"Processing request for path: {request.url.path}")
        # Public allowlist
        if request.url.path in PUBLIC_PATHS:
            logger.info(f"'{request.url.path}' is in the PUBLIC_PATHS list. No Authentication required.")
            return await call_next(request)

        # Allow-list PEC origin check for all MCP paths (including noauth)
        origin = request.headers.get("Origin")
        if ALLOWED_ORIGINS and origin and origin not in ALLOWED_ORIGINS:
            logger.info(f"Origin '{origin}' not allowed")
            return _forbidden("origin_not_allowed", f"Origin '{origin}' not allowed")

        # Path-based no-auth override for Streamable HTTP
        if request.url.path.startswith(PUBLIC_MCP_PREFIX):
            logger.info(f"Path '{request.url.path}' matched no-auth prefix, allowing anonymous access")
            return await self._run_with_auth(request, {"mode": "anonymous_path_override"}, call_next)

        # Normal multi-auth flow starts here
        auth_header = request.headers.get("Authorization", "")
        bearer = auth_header[len("Bearer ") :].strip() if auth_header.startswith("Bearer ") else None

        if not bearer:
            logger.info("Missing Authorization: Bearer header")
            return _unauthorized("unauthorized", "Missing Authorization: Bearer header", request)

        # API key path
        if bearer in API_KEYS:
            logger.info("API key authentication successful")
            return await self._run_with_auth(request, {"mode": "api_key"}, call_next)

        # Entra JWT path
        if not (self.jwks_client and AUTH_SERVER_URL and MCP_APP_ID):
            logger.info("Server misconfiguration for JWT validation")
            return _unauthorized(
                "server_misconfigured",
                "JWT validation requires TENANT_ID and MCP_APP_ID",
                request,
            )

        try:
            logger.info(f"Validating JWT token, with {AUTH_SERVER_URL} as issuer")
            signing_key = self.jwks_client.get_signing_key_from_jwt(bearer)
            payload = jwt.decode(
                bearer,
                signing_key.key,
                algorithms=["RS256"],
                audience=MCP_APP_ID,
                issuer=AUTH_SERVER_URL,
            )
        except InvalidTokenError as ex:
            logger.error(f"Invalid token: {ex}")
            return _unauthorized("invalid_token", str(ex), request)

        token_scopes = set((payload.get("scp") or "").split()) if isinstance(payload.get("scp"), str) else set()
        token_roles = set(payload.get("roles") or [])
        # Support both v1 'appid' and v2 'azp' claims for client identity
        app_id = payload.get("appid") or payload.get("azp")

        if REQUIRED_SCOPES and not (REQUIRED_SCOPES <= token_scopes):
            logger.info(f"Insufficient scopes: {sorted(token_scopes)}")
            return _forbidden("insufficient_scope", f"Required scopes: {sorted(REQUIRED_SCOPES)}")
        if REQUIRED_ROLES and not (REQUIRED_ROLES <= token_roles):
            logger.info(f"Insufficient roles: {sorted(token_roles)}")
            return _forbidden("insufficient_roles", f"Required roles: {sorted(REQUIRED_ROLES)}")

        subtype = "entra_id"
        if app_id and app_id in ALLOWED_AGENT_IDS:
            subtype = "agent_identity"
        elif app_id and app_id in ALLOWED_PROJECT_MIS:
            subtype = "project_managed_identity"

        auth_data = {
            "mode": "entra_jwt",
            "subtype": subtype,
            "claims": {
                "appid": app_id,
                "scp": sorted(token_scopes),
                "roles": sorted(token_roles),
            },
        }
        logger.info(f"JWT authentication successful, mode: {subtype}")
        return await self._run_with_auth(request, auth_data, call_next)


# -----------------------------
# MCP server (tools/resources/prompts)
# -----------------------------
mcp = FastMCP(
    "Multi-Auth MCP",
    json_response=True,
    streamable_http_path="/",
    host="0.0.0.0",
    port=PORT,
    # Explicitly disabling DNS rebinding protection and allowing all hosts
    # as we are handling security in the outer middleware.
    transport_security=TransportSecuritySettings(allowed_hosts=["*"], enable_dns_rebinding_protection=False),
)


@mcp.tool()
def get_access_flow() -> str:
    """Returns the current authentication flow used to access the server."""
    logger.info("get_access_flow called")
    info = auth_ctx.get()
    mode = info.get("mode")
    id = info.get("claims", {}).get("appid", "")
    access_info = "Current authentication flow is Unknown."

    if mode == "anonymous_path_override":
        access_info = "Current authentication flow is NoAuth."

    if mode == "api_key":
        access_info = "Current authentication flow is ApiKey."

    if mode == "entra_jwt":
        subtype = info.get("subtype")
        if subtype == "agent_identity":
            access_info = f"Current authentication flow is EntraID (Agentic ID). id: {id}"
        if subtype == "project_managed_identity":
            access_info = f"Current authentication flow is EntraID (Project Managed Identity). id: {id}"
        else:
            access_info = f"Current authentication flow is OAuth. id: {id}"

    logger.info(f"Returning access info: {access_info}")
    return access_info


@mcp.tool()
def add(a: int, b: int) -> int:
    logger.info(f"add called with a={a}, b={b}")
    return a + b


@mcp.tool()
def whoami() -> dict:
    logger.info("whoami called")
    return {"note": "Use /authz to inspect the request auth context."}


@mcp.tool()
async def long_running_operation(steps: int, delay_seconds: float, ctx: Context) -> str:
    """Simulates a long-running operation that reports progress via notifications.

    Args:
        steps: Number of steps to simulate (must be >= 1).
        delay_seconds: Seconds to wait between each step.
    """
    steps = max(1, steps)
    delay_seconds = max(0.1, min(delay_seconds, 30.0))

    logger.info(f"long_running_operation started: steps={steps}, delay={delay_seconds}s")

    for i in range(1, steps + 1):
        await asyncio.sleep(delay_seconds)
        message = f"Completed step {i}/{steps}"
        await ctx.report_progress(progress=i, total=steps, message=message)
        logger.info(f"Progress reported: {i}/{steps} - {message}")

    result = f"Operation finished successfully after {steps} steps."
    logger.info(result)
    return result


@mcp.resource("greeting://{name}")
def greeting(name: str) -> str:
    logger.info(f"greeting called with name={name}")
    return f"Hello, {name}!"


@mcp.prompt()
def greet_template(name: str, style: str = "friendly") -> str:
    logger.info(f"greet_template called with name={name}, style={style}")
    return f"Write a {style} greeting for {name}."


# -----------------------------
# Extra routes
# -----------------------------
async def healthz(_: Request):
    logger.info("Healthz path accessed")
    return PlainTextResponse("ok")


async def show_authz(request: Request):
    info = getattr(request.state, "auth", {"mode": "none"})
    logger.info(f"Authz path accessed, auth info: {info}")
    return JSONResponse(info)


async def prm(request: Request):
    logger.info(f"'{PRM_PATH}' endpoint reached.")
    return JSONResponse(build_prm(request))


# -----------------------------
# ASGI app (Streamable HTTP mounted at /mcp and /noauth/mcp)
# -----------------------------


@contextlib.asynccontextmanager
async def lifespan(app: Starlette):
    # This starts the StreamableHTTP session manager (task group)
    async with mcp.session_manager.run():
        yield


inner = mcp.streamable_http_app()
inner.router.redirect_slashes = False


def _rewrite_host_in_scope(scope):
    """
    Rewrite the Host header to 127.0.0.1 to bypass FastMCP's strict host checking.
    We are behind a proxy (e.g. Azure Container Apps) and have already validated Origin/Auth.
    """
    # Simply remove the host header to force fallback behaviors or avoid mismatch
    if scope["type"] == "http":
        headers = scope.get("headers", [])
        new_headers = []
        host_replaced = False
        # Use 127.0.0.1 which is the default host for FastMCP if not specified differently essentially
        target_host = b"127.0.0.1"

        for name, value in headers:
            if name == b"host":
                new_headers.append((b"host", target_host))
                host_replaced = True
            else:
                new_headers.append((name, value))

        if not host_replaced:
            new_headers.append((b"host", target_host))

        scope["headers"] = new_headers


async def permissive_inner_app(scope, receive, send):
    """
    Wrapper to handle empty path (Mount strips prefix, leaving empty string if no trailing slash).
    Starlette Route requires path to start with '/', so we explicitly rewrite '' -> '/'.
    """
    if scope["type"] == "http":
        logger.info(f"permissive_inner_app received path: '{scope.get('path')}'")
        if scope["path"] == "":
            logger.info("Rewriting empty path to '/'")
            scope["path"] = "/"

        # Rewriting Host header to bypass inner app's strict host check
        _rewrite_host_in_scope(scope)

    await inner(scope, receive, send)


class ASGIAppResponse(Response):
    """
    Adapter to allow an ASGI app to be returned as a Starlette Response.
    Used to bridge Route('/mcp') -> inner app (treating it as '/').
    """

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        # Rewrite path to '/' for the inner app (since we matched the root /mcp)
        # Note: scope here is the scope passed to the Response, which is the original request scope
        # but we need to ensure path is what inner expects.
        # When invoked via Route('/mcp'), path is '/mcp'.
        # We want inner to see '/'.
        # However, calling app(scope...) passes the scope.

        # We construct a modified scope or modify it in place?
        # Modifying in place is risky if side effects occur, but here it is the end of the chain.
        scope["path"] = "/"
        scope["root_path"] = scope.get("root_path", "") + "/mcp"

        # Rewriting Host header to bypass inner app's strict host check
        _rewrite_host_in_scope(scope)

        await self.app(scope, receive, send)


async def mcp_home_shim(request: Request):
    logger.info("Shim: Explicit /mcp route hit, delegating to inner app")
    return ASGIAppResponse(inner)


logger.info("Inner MCP app routes:")
for r in inner.routes:
    logger.info(f"INNER: {repr(r)}")


app = Starlette(
    routes=[
        # Public paths
        Route("/healthz", healthz),
        Route("/authz", show_authz),
        # PRM paths
        Route(PRM_PATH, prm),
        Route(f"{PRM_PATH}/mcp", prm),
        # Protected MCP paths (Shim for exact /mcp + Mount for subpaths)
        Route(AUTH_MCP_PREFIX, mcp_home_shim, methods=["GET", "POST", "DELETE"]),
        Mount(AUTH_MCP_PREFIX, app=permissive_inner_app),
        # Public-by-path paths (Shim for exact /noauth/mcp + Mount for subpaths)
        Route(PUBLIC_MCP_PREFIX, mcp_home_shim, methods=["GET", "POST", "DELETE"]),
        Mount(PUBLIC_MCP_PREFIX, app=permissive_inner_app),
        # Mount(f"{PUBLIC_MCP_PREFIX}/", app=inner),
    ],
    lifespan=lifespan,  # <-- critical
)

logger.info("Outer MCP app routes:")
for r in app.routes:
    logger.info(f"OUTER: {repr(r)}")

app.router.redirect_slashes = False  # Disable automatic slash redirects

app.add_middleware(MultiAuthMiddleware)

app.add_middleware(
    CORSMiddleware,
    allow_origins=list(ALLOWED_ORIGINS) if ALLOWED_ORIGINS else ["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)
