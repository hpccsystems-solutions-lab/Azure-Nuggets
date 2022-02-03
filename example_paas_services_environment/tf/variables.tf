variable "resource_group_location" {
  default = "eastus2"
  description   = "Location of the resource group"
}

variable "resource_group_name" {
  default = "rg_tombolo_example_eastus2"
  description   = "Resource group name"
}

variable "vnet_name" {
  default = "vnet_tombolo_example_eastus2"
  description   = "VNet name"
}