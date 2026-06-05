#!/usr/bin/env bash
# =============================================================================
# build_and_push.sh — Build the multi-auth MCP image and push it to ACR.
#
# IMPORTANT: --platform linux/amd64 is required. Azure Container Apps runs on
# Linux AMD64; an arm64 image (from Apple Silicon) will fail to start with
# `exec format error`.
#
# Usage:
#   export ACR_NAME="crprivateagentdevd0bl"   # your ACR name (no .azurecr.io)
#   export IMAGE_TAG="v1"                     # optional; defaults to "latest"
#   ./build_and_push.sh
# =============================================================================
set -euo pipefail

ACR_NAME="${ACR_NAME:?Set ACR_NAME to your Azure Container Registry name (no .azurecr.io suffix)}"
IMAGE_NAME="${IMAGE_NAME:-multi-auth-mcp}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Logging in to ACR: ${ACR_NAME}"
az acr login --name "${ACR_NAME}"

echo "==> Building and pushing: ${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG} (linux/amd64)"
docker buildx build \
  --platform linux/amd64 \
  --push \
  -t "${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}" \
  "${SCRIPT_DIR}"

echo ""
echo "Done. Image pushed to: ${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}"
echo ""
echo "To roll the running container app onto the new image:"
echo "  az containerapp update -n mcp-http-server -g <resource-group> \\"
echo "    --image ${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}"
