terraform {
  required_version = ">= 1.8"

  required_providers {
    fabric = {
      source  = "microsoft/fabric"
      version = ">= 1.0"
    }
    external = {
      source  = "hashicorp/external"
      version = ">= 2.3"
    }
  }
}
