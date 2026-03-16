#!/usr/bin/env bash
# generate-wg0-conf.sh — Generate a WireGuard client wg0.conf from Terraform outputs.
#
# Prerequisites:
#   - terraform CLI in PATH, with a valid state in the current directory
#   - wireguard-tools installed (provides the 'wg' command)
#
# Usage:
#   ./generate-wg0-conf.sh <client-private-key-file> <server-private-key-file> [output-file]
#
# Arguments:
#   client-private-key-file  Path to file containing the client WireGuard private key
#   server-private-key-file  Path to file containing the server WireGuard private key
#   output-file              Path to write the config (default: ./wg0.conf)
#
# Example:
#   wg genkey > client.key
#   ./generate-wg0-conf.sh client.key server.key
#   sudo cp wg0.conf /etc/wireguard/wg0.conf
#   sudo wg-quick up wg0

set -euo pipefail

# ── Arguments ────────────────────────────────────────────────────────────────
CLIENT_KEY_FILE="${1:?Usage: $0 <client-private-key-file> <server-private-key-file> [output-file]}"
SERVER_KEY_FILE="${2:?Usage: $0 <client-private-key-file> <server-private-key-file> [output-file]}"
OUTPUT_FILE="${3:-./wg0.conf}"

# ── Read key files ───────────────────────────────────────────────────────────
if [[ ! -f "$CLIENT_KEY_FILE" ]]; then
  echo "Error: Client private key file not found: $CLIENT_KEY_FILE" >&2
  exit 1
fi

if [[ ! -f "$SERVER_KEY_FILE" ]]; then
  echo "Error: Server private key file not found: $SERVER_KEY_FILE" >&2
  exit 1
fi

CLIENT_PRIVATE_KEY=$(<"$CLIENT_KEY_FILE")
SERVER_PRIVATE_KEY=$(<"$SERVER_KEY_FILE")

# Trim whitespace/newlines
CLIENT_PRIVATE_KEY="${CLIENT_PRIVATE_KEY%%[[:space:]]}"
SERVER_PRIVATE_KEY="${SERVER_PRIVATE_KEY%%[[:space:]]}"

# ── Derive server public key ─────────────────────────────────────────────────
SERVER_PUBLIC_KEY=$(echo "$SERVER_PRIVATE_KEY" | wg pubkey)

# ── Read Terraform outputs ───────────────────────────────────────────────────
echo "Reading Terraform outputs..."
ENDPOINT_IP=$(terraform output -raw wireguard_vm_public_ip)

if [[ -z "$ENDPOINT_IP" ]]; then
  echo "Error: wireguard_vm_public_ip output is empty. Has terraform apply completed?" >&2
  exit 1
fi

# ── Gather VNet CIDR from Terraform state ────────────────────────────────────
VNET_CIDR=$(terraform show -json | python3 -c "
import sys, json
state = json.load(sys.stdin)
for r in state.get('values', {}).get('root_module', {}).get('resources', []):
    if r.get('type') == 'azurerm_resource_group':
        continue
    if r.get('type') == 'azurerm_virtual_network' or 'virtualnetwork' in r.get('type', ''):
        addrs = r.get('values', {}).get('address_space', [])
        if addrs:
            print(addrs[0])
            sys.exit(0)
# Fallback: try from child modules
for mod in state.get('values', {}).get('root_module', {}).get('child_modules', []):
    for r in mod.get('resources', []):
        addrs = r.get('values', {}).get('address_space', [])
        if addrs:
            print(addrs[0])
            sys.exit(0)
print('10.0.0.0/20')
" 2>/dev/null)

# WireGuard tunnel subnet (must match cloud-init config)
WG_TUNNEL_SUBNET="10.100.0.0/24"
WG_CLIENT_ADDRESS="10.100.0.2/24"
WG_DNS="10.100.0.1"
WG_PORT="51820"

# ── Generate wg0.conf ───────────────────────────────────────────────────────
cat > "$OUTPUT_FILE" <<EOF
[Interface]
Address    = ${WG_CLIENT_ADDRESS}
PrivateKey = ${CLIENT_PRIVATE_KEY}
# Route DNS through the VPN via dnsmasq running on the WireGuard server.
# dnsmasq (10.100.0.1) forwards to Azure DNS (168.63.129.16) locally,
# which resolves privatelink zones (e.g., privatelink.*.aroapp.io)
# to private endpoint IPs.
# NOTE: 168.63.129.16 is host-local in Azure and cannot be reached
# directly through the tunnel — a DNS forwarder on the VM is required.
DNS        = ${WG_DNS}

[Peer]
PublicKey  = ${SERVER_PUBLIC_KEY}
Endpoint   = ${ENDPOINT_IP}:${WG_PORT}
AllowedIPs = ${VNET_CIDR}, ${WG_TUNNEL_SUBNET}
PersistentKeepalive = 25
EOF

echo "Generated ${OUTPUT_FILE}"
echo ""
echo "  Endpoint : ${ENDPOINT_IP}:${WG_PORT}"
echo "  AllowedIPs : ${VNET_CIDR}, ${WG_TUNNEL_SUBNET}"
echo ""
echo "To activate:"
echo "  sudo cp ${OUTPUT_FILE} /etc/wireguard/wg0.conf"
echo "  sudo wg-quick up wg0"
