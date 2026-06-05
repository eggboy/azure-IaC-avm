output "public_ip_address" {
  description = "The public IP address of the GPU VM."
  value       = data.azurerm_public_ip.vm.ip_address
}

output "resource_group_name" {
  description = "The name of the resource group."
  value       = azurerm_resource_group.this.name
}

output "ssh_command" {
  description = "SSH command to connect to the GPU VM."
  value       = "ssh ${var.admin_username}@${data.azurerm_public_ip.vm.ip_address}"
}

output "vm_id" {
  description = "The resource ID of the GPU VM."
  value       = module.vm.resource_id
}

output "vscode_remote_ssh" {
  description = "VS Code Remote-SSH command to open the VM workspace."
  value       = "code --remote ssh-remote+${var.admin_username}@${data.azurerm_public_ip.vm.ip_address} /home/${var.admin_username}"
}
