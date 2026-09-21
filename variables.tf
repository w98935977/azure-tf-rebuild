variable "subscription_id" {
  type = string
}
variable "location" {
  type    = string
  default = "eastasia"
}
variable "prefix" {
  type    = string
  default = "tommy-tf-rebuild"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.prefix))
    error_message = "Use 3-31 lowercase letters, digits or hyphens; start with a letter."
  }
}
variable "admin_cidr" {
  type = string
  validation {
    condition     = can(cidrnetmask(var.admin_cidr)) && endswith(var.admin_cidr, "/32")
    error_message = "Use your CURRENT public IPv4 address with /32."
  }
}
variable "ssh_public_key_path" {
  type = string
}
variable "vm_size" {
  type    = string
  default = "Standard_B1s"
}
variable "create_compute" {
  type    = bool
  default = false
}
