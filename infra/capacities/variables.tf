# Names, region and subscription come from ../platform.json, written by
# bootstrap/. Only sizing and extra admins are set here.

variable "capacity_skus" {
  description = "Capacity size per environment: F2, F4, F8, ... F2048."
  type        = map(string)
  default = {
    Dev  = "F2"
    Prod = "F2"
  }

  validation {
    condition     = alltrue([for sku in values(var.capacity_skus) : can(regex("^F[0-9]+$", sku))])
    error_message = "SKUs must look like F2, F4, F64."
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
