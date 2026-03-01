variable "enable_telemetry" {
  type        = bool
  default     = true
  nullable    = false
  description = "Controls whether telemetry is enabled for AVM modules."
}

variable "instance" {
  type        = string
  default     = "001"
  description = "The instance number for resource naming (e.g. 001, 002). Used as the ### suffix per CAF convention."

  validation {
    condition     = can(regex("^[0-9]{3}$", var.instance))
    error_message = "Instance must be a three-digit zero-padded number (e.g. 001)."
  }
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "The environment name (e.g. dev, stg, prd) used in resource naming."

  validation {
    condition     = contains(["dev", "stg", "prd"], var.environment)
    error_message = "Environment must be dev, stg, or prd."
  }
}

variable "location" {
  type        = string
  default     = "eastus"
  description = "The Azure region where the resources will be deployed."

  validation {
    condition     = can(regex("^[a-z]+[a-z0-9]*$", var.location))
    error_message = "Location must be a valid Azure region name (lowercase, no spaces)."
  }
}

variable "project" {
  type        = string
  default     = "aml"
  description = "The project name used in resource naming."
}

variable "subnet_prefixes" {
  type = object({
    compute   = string
    ml        = string
    pe        = string
    wireguard = string
  })
  default = {
    compute   = "10.0.2.0/24"
    ml        = "10.0.1.0/24"
    pe        = "10.0.3.0/24"
    wireguard = "10.0.5.0/24"
  }
  nullable    = false
  description = "The address prefixes for each subnet. The wireguard subnet hosts the WireGuard VPN gateway VM."
}

variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags to apply to all resources."
}

variable "vm_admin_username" {
  type        = string
  default     = "azureadmin"
  description = "The admin username for the WireGuard VPN gateway VM. Authentication uses an auto-generated SSH key pair."
}

variable "vm_size" {
  type        = string
  default     = "Standard_D2s_v3"
  description = "The size (SKU) of the WireGuard VPN gateway VM."
}

variable "vm_zone" {
  type        = string
  default     = "1"
  description = "The availability zone for the WireGuard VPN gateway VM. Set to null for regions without zone support."
}

variable "vnet_address_space" {
  type        = list(string)
  default     = ["10.0.0.0/16"]
  nullable    = false
  description = "The address space for the virtual network."
}

variable "wireguard_client_public_key" {
  type        = string
  description = "WireGuard public key of the first VPN client. Generate with: wg genkey | wg pubkey"
}

variable "wireguard_server_private_key" {
  type        = string
  sensitive   = true
  description = "WireGuard server private key. Generate with: wg genkey"
}
