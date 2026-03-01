variable "environment" {
  description = "The deployment environment (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "kubernetes_version" {
  description = "The Kubernetes version for the AKS cluster (e.g., 1.31)"
  type        = string
  default     = "1.33.6"
}

variable "aks_node_vm_size" {
  description = "The VM size for the AKS default node pool"
  type        = string
  default     = "Standard_D2plds_v6"
}

variable "ssh_public_key" {
  description = "SSH public key for AKS Linux nodes. Contents of ~/.ssh/id_rsa.pub"
  type        = string
}

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "koreacentral"
}

variable "tags" {
  description = "A map of tags to assign to all resources"
  type        = map(string)
  default     = {}
}

variable "vnet_address_space" {
  description = "The address space for the virtual network"
  type        = list(string)
  default     = ["100.64.0.0/16"]
}

variable "vm_admin_username" {
  description = "The admin username for the WireGuard VPN gateway VM"
  type        = string
  default     = "azureadmin"
}

variable "vm_size" {
  description = "The size (SKU) of the WireGuard VPN gateway VM"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "vm_zone" {
  description = "The availability zone for the WireGuard VPN gateway VM. Set to null for regions without zone support."
  type        = string
  default     = "1"
}

variable "wireguard_client_public_key" {
  description = "WireGuard public key of the first VPN client. Generate with: wg genkey | tee client.key | wg pubkey"
  type        = string
}

variable "wireguard_server_private_key" {
  description = "WireGuard server private key. Generate with: wg genkey"
  type        = string
  sensitive   = true
}

variable "workload" {
  description = "The workload or application name used in resource naming"
  type        = string
  default     = "aks"
}
