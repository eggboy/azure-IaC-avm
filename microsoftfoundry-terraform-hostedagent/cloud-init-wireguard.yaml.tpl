#cloud-config
# Installs WireGuard and configures it as a VPN gateway into ${vnet_cidr}.
# The server tunnel address is 10.100.0.1/24; clients get addresses in that range.
# dnsmasq runs as a DNS forwarder on 10.100.0.1 so VPN clients can resolve
# Azure private DNS zones (privatelink.*) via the VNet-linked 168.63.129.16.

packages:
  - wireguard
  - iptables
  - iptables-persistent
  - dnsmasq

write_files:
  # WireGuard server configuration
  - path: /etc/wireguard/wg0.conf
    permissions: "0600"
    owner: root:root
    content: |
      [Interface]
      Address    = 10.100.0.1/24
      ListenPort = 51820
      PrivateKey = ${server_private_key}

      # NAT: masquerade WireGuard traffic as the VM's private IP so return traffic is routed correctly.
      # %i expands to the WireGuard interface name (wg0).
      # The primary NIC is auto-detected via the default route.
      # NOTE: All commands on ONE line — wg-quick's sed-based stripping does not
      # reliably handle backslash line continuations, causing wg setconf to fail.
      PostUp   = NIC=$(ip -4 route show default | awk '{print $5}'); iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $NIC -j MASQUERADE
      PostDown = NIC=$(ip -4 route show default | awk '{print $5}'); iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $NIC -j MASQUERADE

      # --- Add one [Peer] block per VPN client ---
      [Peer]
      # Client 1
      PublicKey  = ${client_public_key}
      AllowedIPs = 10.100.0.2/32

  # Enable IPv4 forwarding (required for NAT routing into the VNET)
  - path: /etc/sysctl.d/99-wireguard.conf
    content: |
      net.ipv4.ip_forward = 1
      net.ipv6.conf.all.forwarding = 1

  # dnsmasq: listen on the WireGuard tunnel IP and forward to Azure DNS.
  # 168.63.129.16 is host-local — only reachable from the VM's own NIC,
  # so VPN clients cannot query it directly through the tunnel.
  - path: /etc/dnsmasq.d/wireguard.conf
    content: |
      listen-address=10.100.0.1
      bind-interfaces
      server=168.63.129.16
      no-resolv
      cache-size=1000

runcmd:
  # Apply sysctl settings immediately
  - sysctl --system
  # Enable and start WireGuard
  - systemctl enable wg-quick@wg0
  - systemctl start wg-quick@wg0
  # Persist iptables rules across reboots
  - netfilter-persistent save
  # Enable and start dnsmasq (after WireGuard so 10.100.0.1 is available)
  - systemctl enable dnsmasq
  - systemctl restart dnsmasq
