output "public_ip" {
  value = azurerm_public_ip.main.ip_address
}

output "postgresql_server" {
  value = azurerm_postgresql_flexible_server.main.name
}

output "openai_endpoint" {
  description = "URL des OpenAI-Endpunkts"
  value       = azurerm_cognitive_account.openai.endpoint
}

output "openai_api_key" {
  description = "API-Key für OpenAI-Zugriff"
  value       = azurerm_cognitive_account.openai.primary_access_key
  sensitive   = true
}
