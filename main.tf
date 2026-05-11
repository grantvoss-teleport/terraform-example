terraform {
  required_providers {
    teleport = {
      source  = "terraform.releases.teleport.dev/gravitational/teleport"
      version = "= 18.7.6"
    }
  }
}

provider "teleport" {
  # addr should point to your Teleport proxy or auth endpoint
  # e.g. "teleport.example.com:443"
  addr               = var.teleport_addr
  identity_file_path = var.teleport_identity_file != "" ? var.teleport_identity_file : null
}
