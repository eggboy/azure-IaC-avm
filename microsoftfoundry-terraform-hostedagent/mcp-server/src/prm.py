from typing import Any, Dict

from starlette.requests import Request

from .config import AUTH_SERVER_URL, RESOURCE_ID, RESOURCE_URL
from .logging_config import get_logger

logger = get_logger("prm")


def build_prm(request: Request) -> Dict[str, Any]:
    logger.info("Building PRM response")
    if RESOURCE_URL:
        resource_url = RESOURCE_URL
        logger.info(f"Using resource URL from environment: {resource_url}")
    else:
        resource_url = f"{request.url.scheme}://{request.url.netloc}/mcp"
        logger.info(f"Using resource URL from request: {resource_url}")
    return {
        "resource": resource_url,
        "authorization_servers": [AUTH_SERVER_URL] if AUTH_SERVER_URL else [],
        "scopes_supported": [
            f"{RESOURCE_ID}/tools.read",
            f"{RESOURCE_ID}/tools.write",
        ]
        if RESOURCE_ID
        else [],
        # "quick_oauth": True,
    }
