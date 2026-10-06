terraform {
  # 1.10+ for ephemeral variables (git_secret never lands in state).
  required_version = ">= 1.10"

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
