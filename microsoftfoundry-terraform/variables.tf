# ==============================================================================
# Required Variables (alphabetical)
# ==============================================================================

variable "apim_publisher_email" {
  type        = string
  default     = ""
  description = "The email address of the API Management publisher. Required when enable_apim is true."
}

variable "apim_publisher_name" {
  type        = string
  default     = ""
  description = "The name of the API Management publisher. Required when enable_apim is true."
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

# ==============================================================================
# Optional Variables (alphabetical)
# ==============================================================================

variable "apim_sku_capacity" {
  type        = number
  default     = 1
  description = "The number of scale units for the API Management Premium SKU."
}

variable "enable_apim" {
  type        = bool
  default     = false
  description = "Whether to provision Azure API Management (PremiumV2, VNet-injected). When false, all APIM-related resources are skipped."
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

variable "first_project_name" {
  type        = string
  default     = "project"
  description = "Name prefix for the first AI Foundry project."
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

variable "location" {
  type        = string
  default     = "eastus2"
  description = "The Azure region where the resources will be deployed."

  validation {
    condition     = can(regex("^[a-z]+[a-z0-9]*$", var.location))
    error_message = "Location must be a valid Azure region name (lowercase, no spaces)."
  }
}

variable "model_capacity" {
  type        = number
  default     = 30
  description = "The tokens per minute (TPM) capacity of the model deployment."
}

variable "model_format" {
  type        = string
  default     = "OpenAI"
  description = "The provider/format of the model."
}

variable "model_name" {
  type        = string
  default     = "gpt-4o-mini"
  description = "The name of the model to deploy."
}

variable "model_sku_name" {
  type        = string
  default     = "GlobalStandard"
  description = "The SKU name for the model deployment."
}

variable "model_version" {
  type        = string
  default     = "2024-07-18"
  description = "The version of the model to deploy."
}

variable "workload" {
  type        = string
  default     = "privateagent"
  description = "The workload name used in resource naming per Azure CAF convention."
}

variable "project_description" {
  type        = string
  default     = "A project for the AI Foundry account with network secured deployed Agent"
  description = "Description for the AI Foundry project."
}

variable "project_display_name" {
  type        = string
  default     = "network secured agent project"
  description = "The display name of the project."
}

variable "subnet_prefixes" {
  type = object({
    agent     = string
    apim      = optional(string, "10.0.4.0/24")
    pe        = string
    mcp       = string
    wireguard = string
  })
  default = {
    agent     = "10.0.0.0/24"
    pe        = "10.0.1.0/24"
    mcp       = "10.0.2.0/24"
    wireguard = "10.0.3.0/24"
  }
  nullable    = false
  description = "The address prefixes for each subnet. Agent and MCP subnets have Container Apps delegation; APIM subnet (used only when enable_apim is true) is delegated to API Management."
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
