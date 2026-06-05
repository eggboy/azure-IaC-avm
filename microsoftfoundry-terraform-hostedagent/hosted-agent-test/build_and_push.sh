#!/usr/bin/env bash
# =============================================================================
# build_and_push.sh — Build the hosted-agent Docker image and push it to ACR
#
# IMPORTANT: You MUST specify --platform linux/amd64 when building.
# Hosted agents run on Linux AMD64 infrastructure. Images built for other
# architectures (e.g. ARM64 on Apple Silicon Macs) will fail to start.
#
# Usage:
#   export ACR_NAME="crprivateagentdevxxxx"
#   ./build_and_push.sh
# =============================================================================
set -euo pipefail

ACR_NAME="${ACR_NAME:?Set ACR_NAME to your Azure Container Registry name}"
IMAGE_NAME="${IMAGE_NAME:-hosted-agent}"
IMAGE_TAG="${IMAGE_TAG:-v1}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_APP_DIR="${SCRIPT_DIR}/agent-app"

echo "==> Logging in to ACR: ${ACR_NAME}"
az acr login --name "${ACR_NAME}"

echo "==> Building and pushing image: ${IMAGE_NAME}:${IMAGE_TAG} (linux/amd64) directly to ACR"
docker buildx build \
  --platform linux/amd64 \
  --push \
  -t "${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}" \
  "${AGENT_APP_DIR}"

echo ""
echo "Done! Image pushed to: ${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}"
echo ""
echo "Next: set ACR_IMAGE and run create_hosted_agent.py"
echo "  export ACR_IMAGE=\"${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}\""
echo "  uv run create_hosted_agent.py"
