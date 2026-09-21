locals {
  tags = {
    Environment = "Lab"
    Project     = "Terraform-Rebuild"
    ManagedBy   = "Terraform"
  }
  nodes = {
    vm01 = { subnet = "10.20.1.0/24", ip = "10.20.1.4" }
    vm02 = { subnet = "10.20.2.0/24", ip = "10.20.2.4" }
  }
}

resource "azurerm_resource_group" "lab" {
  name     = "rg-${var.prefix}"
  location = var.location
  tags     = local.tags
}
resource "azurerm_virtual_network" "lab" {
  name                = "vnet-${var.prefix}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.20.0.0/16"]
  tags                = local.tags
}
resource "azurerm_subnet" "lab" {
  for_each                        = local.nodes
  name                            = "snet-${each.key}"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.lab.name
  address_prefixes                = [each.value.subnet]
  default_outbound_access_enabled = false
}
resource "azurerm_network_security_group" "lab" {
  for_each            = local.nodes
  name                = "nsg-${each.key}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}
resource "azurerm_subnet_network_security_group_association" "lab" {
  for_each                  = local.nodes
  subnet_id                 = azurerm_subnet.lab[each.key].id
  network_security_group_id = azurerm_network_security_group.lab[each.key].id
}
resource "azurerm_network_security_rule" "ssh_home" {
  for_each                    = local.nodes
  name                        = "Allow-SSH-Admin"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = var.admin_cidr
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.lab[each.key].name
}
resource "azurerm_network_security_rule" "deny_other_ssh" {
  for_each                    = local.nodes
  name                        = "Deny-Other-SSH"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.lab[each.key].name
}
resource "azurerm_network_security_rule" "http_vm01" {
  name                        = "Allow-8080-VM01"
  priority                    = 200
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8080"
  source_address_prefix       = "${local.nodes.vm01.ip}/32"
  destination_address_prefix  = local.nodes.vm02.ip
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.lab["vm02"].name
}
resource "azurerm_network_security_rule" "deny_other_http" {
  name                        = "Deny-Other-8080"
  priority                    = 210
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "8080"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.lab["vm02"].name
}
resource "azurerm_public_ip" "lab" {
  for_each            = var.create_compute ? local.nodes : {}
  name                = "pip-${each.key}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags
}
resource "azurerm_network_interface" "lab" {
  for_each            = var.create_compute ? local.nodes : {}
  name                = "nic-${each.key}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.lab[each.key].id
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.ip
    public_ip_address_id          = azurerm_public_ip.lab[each.key].id
  }
}
resource "azurerm_linux_virtual_machine" "lab" {
  for_each                        = var.create_compute ? local.nodes : {}
  name                            = "${var.prefix}-${each.key}"
  computer_name                   = each.key
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = azurerm_resource_group.lab.location
  size                            = var.vm_size
  admin_username                  = "azureuser"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.lab[each.key].id]
  tags                            = local.tags
  admin_ssh_key {
    username   = "azureuser"
    public_key = file(pathexpand(var.ssh_public_key_path))
  }
  os_disk {
    name                 = "osdisk-${each.key}"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 32
  }
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", {
    node_name = each.key
  }))
  depends_on = [
    azurerm_subnet_network_security_group_association.lab,
    azurerm_network_security_rule.ssh_home,
    azurerm_network_security_rule.deny_other_ssh,
    azurerm_network_security_rule.http_vm01,
    azurerm_network_security_rule.deny_other_http
  ]
}
