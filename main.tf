terraform {
  required_providers {
    teleport = {
      source  = "terraform.releases.teleport.dev/gravitational/teleport"
      version = "= 18.7.6"
    }
    external = {
      source  = "registry.terraform.io/hashicorp/external"
      version = ">= 2.3.0"
    }
  }
}

provider "teleport" {
  addr               = var.teleport_addr
  identity_file_path = var.teleport_identity_file != "" ? var.teleport_identity_file : null
}
