variable "aro_cluster_version" {
  description = "The OpenShift version for the ARO cluster (e.g., 4.16.39)"
  type        = string
  default     = "4.16.39"
}

variable "aro_master_vm_size" {
  description = "The VM size for the ARO master (control plane) nodes"
  type        = string
  default     = "Standard_D8as_v5"
}

variable "aro_rp_client_id" {
  description = "The application (client) ID of the Azure Red Hat OpenShift resource provider service principal"
  type        = string
  default     = "f1dd0a37-89c6-4e07-bcd1-ffd3d43d8875"
}

variable "aro_worker_disk_size_gb" {
  description = "The disk size in GB for ARO worker nodes"
  type        = number
  default     = 128
}

variable "aro_worker_node_count" {
  description = "The number of ARO worker nodes"
  type        = number
  default     = 3
}

variable "aro_worker_vm_size" {
  description = "The VM size for the ARO worker nodes"
  type        = string
  default     = "Standard_D8as_v5"
}

variable "environment" {
  description = "The deployment environment (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "location" {
  description = "The Azure region where resources will be deployed"
  type        = string
  default     = "koreacentral"
}

variable "pull_secret" {
  description = "Red Hat pull secret for the ARO cluster. Obtain from https://console.redhat.com/openshift/install/pull-secret"
  type        = string
  default     = null
  sensitive   = true
}

variable "tags" {
  description = "A map of tags to assign to all resources"
  type        = map(string)
  default     = {}
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

variable "vnet_address_space" {
  description = "The address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/20"]
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
  default     = "aro"
}
