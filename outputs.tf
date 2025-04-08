output "vm_public_ip" {
  value = azurerm_public_ip.main.ip_address
}

output "vm_username" {
  value = var.admin_username
}


output "postgresql_server" {
  value = azurerm_postgresql_flexible_server.main.name
}

output "app_url" {
  value = "http://${azurerm_public_ip.main.ip_address}:5000"
}
