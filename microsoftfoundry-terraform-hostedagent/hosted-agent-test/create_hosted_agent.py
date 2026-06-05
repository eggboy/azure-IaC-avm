#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "azure-ai-projects>=2.1.0",
#     "azure-identity>=1.19",
# ]
# ///
"""Create and register a hosted agent version on Microsoft Foundry.

This script:
  1. Creates a hosted agent version from a container image in ACR.
  2. Prints the agent name, id, and version for use with start/invoke scripts.

Prerequisites:
    - Account-level capability host with enablePublicHostingEnvironment=true
    - Container image pushed to ACR
    - Project managed identity has AcrPull on the ACR
    - azure-ai-projects >= 2.0.0

Ref:
    https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/hosted-agents

Usage::

    export PROJECT_ENDPOINT="https://<account>.services.ai.azure.com/api/projects/<project>"
    export ACR_IMAGE="<acr>.azurecr.io/hosted-agent:v1"
    uv run create_hosted_agent.py
"""

import os
import sys

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    AgentProtocol,
    ContainerConfiguration,
    HostedAgentDefinition,
    ProtocolVersionRecord,
)
from azure.identity import DefaultAzureCredential

# ── Configuration ────────────────────────────────────────────────────────
PROJECT_ENDPOINT = os.environ.get("PROJECT_ENDPOINT", "")
ACR_IMAGE = os.environ.get("ACR_IMAGE", "")
AGENT_NAME = os.environ.get("AGENT_NAME", "my-hosted-agent")
MODEL_NAME = os.environ.get("MODEL_NAME", "gpt-4o-mini")
CPU = os.environ.get("AGENT_CPU", "1")
MEMORY = os.environ.get("AGENT_MEMORY", "2Gi")


def main() -> None:
    """Create a hosted agent version from an ACR container image."""
    if not PROJECT_ENDPOINT:
        print("ERROR: Set PROJECT_ENDPOINT env var to your Foundry project endpoint.", file=sys.stderr)
        print("  e.g. https://<account>.services.ai.azure.com/api/projects/<project>", file=sys.stderr)
        sys.exit(1)
    if not ACR_IMAGE:
        print("ERROR: Set ACR_IMAGE env var to the full ACR image URL.", file=sys.stderr)
        print("  e.g. myacr.azurecr.io/hosted-agent:v1", file=sys.stderr)
        sys.exit(1)

    print(f"Project endpoint : {PROJECT_ENDPOINT}")
    print(f"Container image  : {ACR_IMAGE}")
    print(f"Agent name       : {AGENT_NAME}")
    print(f"CPU / Memory     : {CPU} / {MEMORY}")
    print()

    client = AIProjectClient(
        endpoint=PROJECT_ENDPOINT,
        credential=DefaultAzureCredential(),
        allow_preview=True,
    )

    env_vars = {
        # AZURE_AI_MODEL_DEPLOYMENT_NAME is read by FoundryChatClient in agent code.
        "AZURE_AI_MODEL_DEPLOYMENT_NAME": MODEL_NAME,
        # Tell Foundry's runtime observability distro to instrument agent_framework
        # and capture sensitive data (input/output messages). Required for the
        # Foundry portal Tracing tab to show GenAI spans with full context.
        # https://github.com/microsoft-foundry/foundry-samples/blob/main/samples/python/hosted-agents/agent-framework/responses/08-observability/agent.yaml
        "ENABLE_INSTRUMENTATION": "true",
        "ENABLE_SENSITIVE_DATA": "true",
    }
    # FOUNDRY_PROJECT_ENDPOINT and APPLICATIONINSIGHTS_CONNECTION_STRING are
    # reserved/platform-injected — passing them returns a ValidationError. The
    # platform automatically populates them at container start time.
    #
    # Optional: forward MCP server URL when set.
    for opt in ("MCP_SERVER_URL",):
        if os.environ.get(opt):
            env_vars[opt] = os.environ[opt]
            print(f"Forwarding env  : {opt} = (set)")

    agent = client.agents.create_version(
        agent_name=AGENT_NAME,
        definition=HostedAgentDefinition(
            cpu=CPU,
            memory=MEMORY,
            container_configuration=ContainerConfiguration(image=ACR_IMAGE),
            protocol_versions=[
                ProtocolVersionRecord(
                    protocol=AgentProtocol.RESPONSES,
                    # Refreshed preview uses semver "1.0.0"; "v1" is legacy.
                    version="1.0.0",
                )
            ],
            environment_variables=env_vars,
        ),
    )

    print(f"Agent created: {agent.name} (id: {agent.id}, version: {agent.version})")
    print()
    print("Next steps:")
    print("  - Invoke directly — compute auto-starts on first request (no manual start).")
    print("  - uv run invoke_hosted_agent.py")


if __name__ == "__main__":
    main()
