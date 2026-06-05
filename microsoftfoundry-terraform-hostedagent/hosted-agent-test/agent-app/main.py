"""Hosted Agent — Microsoft Agent Framework + Private MCP.

Refreshed-preview hosting model. Connects to a **private MCP server**
(Streamable HTTP) reachable through the hosted-agent's networkInjections subnet.

Observability is enabled via env vars (set by `create_hosted_agent.py`):
    ENABLE_INSTRUMENTATION=true
    ENABLE_SENSITIVE_DATA=true
The Foundry platform's `microsoft-opentelemetry` distro wires up exporters
automatically using the platform-injected APPLICATIONINSIGHTS_CONNECTION_STRING.
Do NOT call configure_azure_monitor() here — it overrides the distro and
strips resource attributes (cloud_RoleName, gen_ai.agent.name), which
prevents the Foundry portal Tracing tab from finding these spans.

Required env vars (injected by Foundry at runtime):
    FOUNDRY_PROJECT_ENDPOINT          - Foundry project endpoint
                                        (https://<account>.services.ai.azure.com/api/projects/<proj>)
    AZURE_AI_MODEL_DEPLOYMENT_NAME    - Model deployment name (e.g. gpt-4o-mini)
    MCP_SERVER_URL                    - Private MCP server URL (Streamable HTTP)
    APPLICATIONINSIGHTS_CONNECTION_STRING
                                      - Platform-injected; consumed by Foundry's
                                        observability distro automatically.

References:
    https://learn.microsoft.com/azure/foundry/agents/concepts/hosted-agents
    https://github.com/microsoft-foundry/foundry-samples/tree/main/samples/python/hosted-agents/agent-framework/responses/08-observability
    https://github.com/microsoft/agent-framework
"""

from __future__ import annotations

import logging
import os
import socket
from urllib.parse import urlparse

from agent_framework import Agent, MCPStreamableHTTPTool
from agent_framework.foundry import FoundryChatClient
from agent_framework_foundry_hosting import ResponsesHostServer
from azure.identity import DefaultAzureCredential

logger = logging.getLogger("hosted_agent")


def _required_env(name: str, fallback: str | None = None) -> str:
    value = os.environ.get(name) or (os.environ.get(fallback) if fallback else None)
    if not value:
        raise RuntimeError(
            f"Required environment variable {name} (or fallback {fallback}) is not set"
        )
    return value


def _log_dns(label: str, url: str) -> None:
    """Log resolved IP for a hostname — handy when diagnosing private DNS."""
    host = urlparse(url).hostname
    if not host:
        logger.warning("%s: cannot parse host from %s", label, url)
        return
    try:
        ip = socket.gethostbyname(host)
        logger.info("DNS %s host=%s -> %s", label, host, ip)
    except OSError as exc:
        logger.warning("DNS %s host=%s FAILED: %s", label, host, exc)


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    project_endpoint = _required_env("FOUNDRY_PROJECT_ENDPOINT", "AZURE_AI_PROJECT_ENDPOINT")
    model_deployment = _required_env("AZURE_AI_MODEL_DEPLOYMENT_NAME", "MODEL_DEPLOYMENT_NAME")
    mcp_url = _required_env("MCP_SERVER_URL")

    # Startup diagnostics: confirm private DNS resolves from the runtime container.
    _log_dns("project", project_endpoint)
    _log_dns("mcp", mcp_url)

    mcp_tool = MCPStreamableHTTPTool(
        name="private-mcp",
        url=mcp_url,
        description="Private MCP server exposing `add`, `whoami`, and other tools.",
        request_timeout=60,
        load_prompts=False,
    )

    client = FoundryChatClient(
        project_endpoint=project_endpoint,
        model=model_deployment,
        credential=DefaultAzureCredential(),
    )

    agent = Agent(
        name="mcp-hosted-agent",
        client=client,
        instructions=(
            "You are a helpful assistant with access to a private MCP server. "
            "When the user asks for arithmetic, ALWAYS call the MCP `add` tool. "
            "When asked who you are, call the MCP `whoami` tool. "
            "After using any tool, explicitly state which tool you used and the result."
        ),
        tools=[mcp_tool],
        # Conversation history is managed by ResponsesHostServer, not the agent.
        default_options={"store": False},
    )

    server = ResponsesHostServer(agent)
    server.run()


if __name__ == "__main__":
    main()
