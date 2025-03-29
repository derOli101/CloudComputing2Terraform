output "public_ip" {
  value = azurerm_public_ip.main.ip_address
}

output "postgresql_server" {
  value = azurerm_postgresql_flexible_server.main.name
}
