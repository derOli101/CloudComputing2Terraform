# === Ressourcen-Grundlage ===

# Ressourcengruppe erstellen
resource "azurerm_resource_group" "main" {
  name     = var.resource_group
  location = var.location
}

# Virtuelles Netzwerk (VNet)
resource "azurerm_virtual_network" "main" {
  name                = "fitness-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
}

# === Netzwerkinfrastruktur ===

# Öffentliche IP für die VM
resource "azurerm_public_ip" "main" {
  name                = "fitness-ip"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Subnetz für die VM
resource "azurerm_subnet" "vm_subnet" {
  name                 = "vm-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
  depends_on           = [azurerm_virtual_network.main]
}

# Subnetz für PostgreSQL mit Delegation
resource "azurerm_subnet" "db_subnet" {
  name                 = "db-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]

  delegation {
    name = "postgresql-delegation"
    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# Netzwerksicherheitsgruppe mit Regeln für SSH, HTTP & Flask-Port
resource "azurerm_network_security_group" "main" {
  name                = "fitness-nsg"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  # Regel für SSH
  security_rule {
    name                       = "allow_ssh"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Regel für HTTP
  security_rule {
    name                       = "allow_http"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Regel für Flask-Port (5000)
  security_rule {
    name                       = "allow_flask"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Netzwerkkarte (NIC) für die VM
resource "azurerm_network_interface" "main" {
  name                = "fitness-nic"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

# Verknüpfung NIC <-> NSG
resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

# === VM ===

# Linux VM mit Ubuntu 20.04
resource "azurerm_linux_virtual_machine" "main" {
  name                  = var.vm_name
  location              = var.location
  resource_group_name   = azurerm_resource_group.main.name
  size                  = "Standard_B1s"
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  disable_password_authentication = false

  network_interface_ids = [azurerm_network_interface.main.id]

  os_disk {
    name                 = "osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }

  # Bootstrap: Environment-File mit Secrets für systemd-Dienst vorbereiten
  custom_data = base64encode(<<-EOF
    #!/bin/bash
    cat <<EOT > /etc/flask-app.env
    ADMIN_PASSWORD="${var.admin_password}"
    POSTGRES_PASSWORD="${var.postgres_password}"
    OPENAI_API_KEY="${var.openai_api_key}"
    DATABASE_URL="postgresql://${azurerm_postgresql_flexible_server.main.administrator_login}:${var.postgres_password}@${azurerm_postgresql_flexible_server.main.fqdn}:5432/${azurerm_postgresql_flexible_server_database.main_database.name}"
    EOT
  EOF
  )
}

# === PostgreSQL Flexible Server ===

# Zufälliger Suffix für DB-Namen (um Überschneidungen zu vermeiden)
resource "random_id" "db" {
  byte_length = 4
}

# PostgreSQL Server mit privatem Zugriff
resource "azurerm_postgresql_flexible_server" "main" {
  name                   = "fitnessdb-${random_id.db.hex}"
  location               = var.location
  resource_group_name    = azurerm_resource_group.main.name
  administrator_login    = var.postgres_admin
  administrator_password = var.postgres_password
  sku_name               = "B_Standard_B1ms"
  version                = "13"
  storage_mb             = 32768

  authentication {
    active_directory_auth_enabled = false
    password_auth_enabled         = true
  }

  delegated_subnet_id         = azurerm_subnet.db_subnet.id
  private_dns_zone_id         = azurerm_private_dns_zone.postgres_dns.id
  public_network_access_enabled = false

  depends_on = [
    azurerm_virtual_network.main,
    azurerm_subnet.db_subnet,
    azurerm_private_dns_zone_virtual_network_link.link
  ]
}

# Datenbank innerhalb des Servers erstellen
resource "azurerm_postgresql_flexible_server_database" "main_database" {
  name      = "fitnessdb"
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "utf8"
  collation = "en_US.utf8"
}

# Azure-interne Firewallregel (Zugriff aus Azure selbst)
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure_services" {
  name       = "AllowAzureServices"
  server_id  = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Private DNS Zone für die DB
resource "azurerm_private_dns_zone" "postgres_dns" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.main.name
}

# VNet <-> DNS Zone Verlinkung
resource "azurerm_private_dns_zone_virtual_network_link" "link" {
  name                  = "vnet-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres_dns.name
  virtual_network_id    = azurerm_virtual_network.main.id
  registration_enabled  = false
}

# === Ansible-Provisioning ===

# Erstelle dynamisches Ansible-Inventar auf Basis der VM-Daten
data "template_file" "ansible_inventory" {
  template = file("${path.module}/ansible_hosts.tmpl")
  vars = {
    vm_ip   = azurerm_public_ip.main.ip_address
    vm_user = var.admin_username
    vm_pass = var.admin_password
  }
}

# Schreibe das Inventar als Datei
resource "local_file" "ansible_inventory" {
  content  = data.template_file.ansible_inventory.rendered
  filename = "${path.module}/ansible/hosts.ini"
}

# Führt Ansible-Provisionierung lokal aus (nachdem VM bereit ist)
resource "null_resource" "provision_app" {
  depends_on = [
    azurerm_linux_virtual_machine.main,
    local_file.ansible_inventory
  ]

  provisioner "local-exec" {
    command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i ${path.module}/ansible/hosts.ini ${path.module}/ansible/playbook.yml"
  }
}

# Zufälliger Suffix (optional, könnte z. B. für Ressourcen verwendet werden)
resource "random_id" "suffix" {
  byte_length = 4
}
