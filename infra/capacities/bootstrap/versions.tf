terraform {
  required_version = ">= 1.8"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 3.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.11"
    }
  }
}
