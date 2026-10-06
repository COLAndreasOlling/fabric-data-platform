variable "subscription_id" {
  description = "Azure subscription that hosts the Fabric capacities."
  type        = string
}

variable "location" {
  description = "Azure region for the capacities. Use the same region as the Fabric tenant home region where possible."
  type        = string
  default     = "westeurope"
}

variable "resource_group_name" {
  description = "Resource group for the capacities."
  type        = string
  default     = "rg-fabric-capacities"
}

variable "create_resource_group" {
  description = "Create the resource group. Set to false to use an existing one."
  type        = bool
  default     = true
}

variable "capacities" {
  description = "Fabric capacities to create. name must be lowercase letters and digits (3-63), unique in Azure; sku is F2, F4, F8, ... F2048."
  type = map(object({
    name = string
    sku  = string
  }))
  default = {
    dev  = { name = "fcdataplatformdev", sku = "F2" }
    prod = { name = "fcdataplatformprod", sku = "F2" }
  }

  validation {
    condition = alltrue([
      for c in values(var.capacities) :
      can(regex("^[a-z][a-z0-9]{2,62}$", c.name)) && can(regex("^F[0-9]+$", c.sku))
    ])
    error_message = "Capacity names must be 3-63 lowercase letters/digits starting with a letter; sku must look like F2, F4, F64."
  }
}

variable "capacity_admins" {
  description = "Extra capacity administrators: user principal names for users, object IDs for service principals. The identity running Terraform is always added."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    workload   = "fabric-data-platform"
    managed_by = "terraform"
  }
}
