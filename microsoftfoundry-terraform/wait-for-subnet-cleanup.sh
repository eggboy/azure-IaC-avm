#!/usr/bin/env bash
# ==============================================================================
# wait-for-subnet-cleanup.sh
#
# Polls an Azure subnet until the service association link (legionservicelink)
# created by networkInjections (Microsoft.App/environments) is removed.
#
# The managed Container Apps Environment lives in a Microsoft-managed
# subscription (hobov3_*) and its async cleanup can take 10+ minutes after
# the AI Services account is destroyed.
#
# Usage:
#   ./wait-for-subnet-cleanup.sh <resource_group> <vnet_name> <subnet_name> \
#                                 [poll_interval_seconds] [timeout_seconds]
# ==============================================================================

set -euo pipefail

RG="${1:?Usage: $0 <resource_group> <vnet_name> <subnet_name> [poll_interval] [timeout]}"
VNET="${2:?}"
SUBNET="${3:?}"
POLL_INTERVAL="${4:-30}"
TIMEOUT="${5:-900}"

elapsed=0

echo "Polling subnet '${SUBNET}' for serviceAssociationLinks cleanup..."
echo "  Resource Group : ${RG}"
echo "  VNet           : ${VNET}"
echo "  Poll interval  : ${POLL_INTERVAL}s"
echo "  Timeout        : ${TIMEOUT}s"

while true; do
  links=$(az network vnet subnet show \
    -g "${RG}" \
    --vnet-name "${VNET}" \
    -n "${SUBNET}" \
    --query "serviceAssociationLinks[].name" \
    -o tsv 2>/dev/null || echo "SUBNET_GONE")

  # Subnet already deleted or no links remain — safe to proceed
  if [ -z "${links}" ] || [ "${links}" = "SUBNET_GONE" ]; then
    echo "Service association links cleared after ${elapsed}s. Subnet is safe to delete."
    exit 0
  fi

  if [ "${elapsed}" -ge "${TIMEOUT}" ]; then
    echo "ERROR: Timed out after ${TIMEOUT}s. Remaining links: ${links}" >&2
    echo "The managed Container Apps Environment may still be cleaning up." >&2
    echo "Wait a few minutes and re-run 'terraform destroy'." >&2
    exit 1
  fi

  echo "[${elapsed}s] Still waiting — active links: ${links}"
  sleep "${POLL_INTERVAL}"
  elapsed=$((elapsed + POLL_INTERVAL))
done
