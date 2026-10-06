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
    fabric = {
      source  = "microsoft/fabric"
      version = ">= 1.0"
    }
  }
}
