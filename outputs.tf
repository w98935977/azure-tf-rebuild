output "resource_group" {
  value = azurerm_resource_group.lab.name
}
output "public_ips" {
  value = { for k, v in azurerm_public_ip.lab : k => v.ip_address }
}
output "private_ips" {
  value = { for k, v in local.nodes : k => v.ip }
}
