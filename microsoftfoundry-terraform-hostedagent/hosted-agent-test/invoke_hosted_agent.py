#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "azure-ai-projects>=2.1.0",
#     "azure-identity>=1.19",
# ]
# ///
"""Invoke a deployed hosted agent using the Responses API.

Refreshed-preview model: each agent has its own dedicated endpoint and
``project.get_openai_client(agent_name=...)`` binds to it. Compute starts
automatically on first request — no manual start needed.

Ref:
    https://learn.microsoft.com/azure/foundry/agents/how-to/migrate-hosted-agent-preview

Usage::

    export PROJECT_ENDPOINT="https://<account>.services.ai.azure.com/api/projects/<project>"
    export AGENT_NAME="my-hosted-agent"
    uv run invoke_hosted_agent.py "What is 2+3?"
"""

import os
import sys

from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential

# ── Configuration ────────────────────────────────────────────────────────
PROJECT_ENDPOINT = os.environ.get("PROJECT_ENDPOINT", "")
AGENT_NAME = os.environ.get("AGENT_NAME", "my-hosted-agent")
DEFAULT_PROMPT = "What is 2 + 3? Use the MCP add tool and report the result."


def main() -> None:
    """Retrieve a hosted agent and invoke it via the Responses API."""
    if not PROJECT_ENDPOINT:
        print("ERROR: Set PROJECT_ENDPOINT env var.", file=sys.stderr)
        sys.exit(1)

    prompt = " ".join(sys.argv[1:]) or DEFAULT_PROMPT

    client = AIProjectClient(
        endpoint=PROJECT_ENDPOINT,
        credential=DefaultAzureCredential(),
        allow_preview=True,
    )

    agent = client.agents.get(agent_name=AGENT_NAME)
    print(f"Agent retrieved: {agent.name} (version: {agent.versions.latest.version})")

    # Dedicated agent endpoint — SDK auto-targets it when agent_name is given.
    openai_client = client.get_openai_client(agent_name=AGENT_NAME)

    print(f"\nSending message: {prompt!r}")
    response = openai_client.responses.create(input=prompt)

    print(f"\nAgent response (output_text):\n{response.output_text or '<empty>'}")
    print(f"\nResponse status: {getattr(response, 'status', '?')}")
    print(f"Output items: {len(response.output or [])}")
    for i, item in enumerate(response.output or []):
        print(f"  [{i}] type={getattr(item, 'type', '?')} role={getattr(item, 'role', '?')}")
        if hasattr(item, "content") and item.content:
            for j, c in enumerate(item.content):
                txt = getattr(c, "text", None) or getattr(c, "output_text", None)
                print(f"       content[{j}] type={getattr(c, 'type', '?')} text={txt!r}")
        for attr in ("name", "arguments", "output", "server_label", "tools"):
            v = getattr(item, attr, None)
            if v:
                print(f"       {attr}={v!r}"[:300])


if __name__ == "__main__":
    main()
