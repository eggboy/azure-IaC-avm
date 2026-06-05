#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "azure-ai-projects>=2.0.0",
#     "azure-identity>=1.19",
# ]
# ///
"""Manage a hosted agent lifecycle: start, stop, list, delete.

Usage::

    export PROJECT_ENDPOINT="https://<account>.services.ai.azure.com/api/projects/<project>"
    export AGENT_NAME="my-hosted-agent"

    uv run manage_hosted_agent.py start --version 1
    uv run manage_hosted_agent.py stop  --version 1
    uv run manage_hosted_agent.py list
    uv run manage_hosted_agent.py delete --version 1
"""

import argparse
import os
import subprocess
import sys
from urllib.parse import urlparse


def parse_endpoint(endpoint: str) -> tuple[str, str]:
    """Extract account name and project name from a Foundry project endpoint.

    Args:
        endpoint: Full project endpoint URL, e.g.
            ``https://<account>.services.ai.azure.com/api/projects/<project>``

    Returns:
        Tuple of (account_name, project_name).

    Raises:
        ValueError: If the endpoint cannot be parsed.
    """
    parsed = urlparse(endpoint)
    if not parsed.hostname:
        raise ValueError(f"Invalid endpoint URL: {endpoint}")
    account_name = parsed.hostname.split(".")[0]
    path_segments = [s for s in parsed.path.split("/") if s]
    # Expected path: /api/projects/<project>
    if len(path_segments) < 3 or path_segments[-2] != "projects":
        raise ValueError(f"Cannot extract project name from endpoint path: {parsed.path}")
    project_name = path_segments[-1]
    return account_name, project_name


def run_az(args: list[str]) -> None:
    """Run an ``az cognitiveservices agent`` sub-command.

    Args:
        args: CLI arguments appended after ``az cognitiveservices agent``.

    Raises:
        subprocess.CalledProcessError: If the command exits with a non-zero code.
    """
    cmd = ["az", "cognitiveservices", "agent", *args]
    print(f"Running: {' '.join(cmd)}\n")
    subprocess.run(cmd, check=True)


def main() -> None:
    """Parse arguments and dispatch to the appropriate agent management command."""
    parser = argparse.ArgumentParser(description="Manage hosted agent lifecycle")
    parser.add_argument("action", choices=["start", "stop", "list", "delete"])
    parser.add_argument("--version", type=str, default="1", help="Agent version (default: 1)")
    parser.add_argument("--min-replicas", type=int, default=0, help="Min replicas (default: 0, scale-to-zero)")
    parser.add_argument("--max-replicas", type=int, default=2, help="Max replicas (default: 2)")
    args = parser.parse_args()

    endpoint = os.environ.get("PROJECT_ENDPOINT", "")
    if not endpoint:
        print("ERROR: Set PROJECT_ENDPOINT env var.", file=sys.stderr)
        sys.exit(1)

    try:
        account_name, project_name = parse_endpoint(endpoint)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)

    agent_name = os.environ.get("AGENT_NAME", "my-hosted-agent")

    common = [
        "--account-name",
        account_name,
        "--project-name",
        project_name,
        "--name",
        agent_name,
    ]

    if args.action == "start":
        run_az(
            [
                "start",
                *common,
                "--agent-version",
                args.version,
                "--min-replicas",
                str(args.min_replicas),
                "--max-replicas",
                str(args.max_replicas),
            ]
        )
    elif args.action == "stop":
        run_az(["stop", *common, "--agent-version", args.version])
    elif args.action == "list":
        run_az(["list-versions", *common])
    elif args.action == "delete":
        run_az(["delete", *common, "--agent-version", args.version])


if __name__ == "__main__":
    main()
