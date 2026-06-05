# --- Required ---

variable "spot_enabled" {
  type        = bool
  default     = true
  nullable    = false
  description = "Use Spot pricing for the GPU VM. Significantly cheaper but the VM can be evicted. Set to false for regular priority."
}

variable "ssh_public_key_file" {
  type        = string
  default     = "~/.ssh/id_rsa.pub"
  description = "Path to the SSH public key file for VM access."
}

# --- Optional ---

variable "admin_username" {
  type        = string
  default     = "azureuser"
  description = "The admin username for the VM."
}

variable "allowed_source_ip" {
  type        = string
  default     = "115.66.16.117"
  description = "Source IP address or CIDR allowed for SSH access. Set to your public IP for security (e.g. \"203.0.113.1\")."
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  nullable    = false
  description = "Controls whether telemetry is enabled for AVM modules."
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
  default     = "malaysiawest"
  description = "The Azure region where the resources will be deployed."

  validation {
    condition     = can(regex("^[a-z]+[a-z0-9]*$", var.location))
    error_message = "Location must be a valid Azure region name (lowercase, no spaces)."
  }
}

variable "os_disk_size_gb" {
  type        = number
  default     = 128
  description = "The size of the OS disk in GB. Minimum 128 GB recommended for CUDA + PyTorch."
}

variable "subnet_address_prefix" {
  type        = string
  default     = "10.0.0.0/24"
  description = "The address prefix for the VM subnet."
}

variable "tags" {
  type        = map(string)
  default     = {}
  nullable    = false
  description = "Tags to apply to all resources."
}

variable "vm_size" {
  type        = string
  default     = "Standard_NC4as_T4_v3"
  description = "The size (SKU) of the GPU VM. Default is the cheapest NVIDIA T4 option."
}

variable "vm_zone" {
  type        = string
  default     = null
  description = "The availability zone for the VM. Set to null for no zone preference, or \"1\", \"2\", \"3\"."
}

variable "vnet_address_space" {
  type        = list(string)
  default     = ["10.0.0.0/16"]
  nullable    = false
  description = "The address space for the virtual network."
}

variable "workload" {
  type        = string
  default     = "pytorchlab"
  description = "The workload name used in resource naming."
}
