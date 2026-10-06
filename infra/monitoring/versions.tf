terraform {
  required_version = ">= 1.10"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = ">= 2.0"
    }
    external = {
      source  = "hashicorp/external"
      version = ">= 2.3"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.11"
    }
  }
}
