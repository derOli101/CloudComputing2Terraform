variable "location" {
  description = "Azure region"
  default     = "francecentral"
}

variable "resource_group" {
  description = "Name der Resource Group"
  default     = "fitness-rg"
}

variable "vm_name" {
  description = "Name der VM"
  default     = "fitness-vm"
}

variable "admin_username" {
  description = "Login-Nutzername für die VM"
  default     = "azureuser"
}

variable "postgres_admin" {
  description = "PostgreSQL-Admin"
  default     = "fitnessadmin"
}

variable "postgres_password" {
  description = "PostgreSQL-Passwort"
  sensitive   = true
}

variable "openai_api_key" {
  description = "API Key für OpenAI"
  type        = string
  sensitive   = true
}

variable "admin_password" {
  description = "Admin-Passwort"
  sensitive = true
}