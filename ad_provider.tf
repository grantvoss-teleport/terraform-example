terraform {
  required_providers {
    teleport = {
      source  = "terraform.releases.teleport.dev/gravitational/teleport"
      version = "= 18.7.6"
    }
    ad = {
      source  = "registry.terraform.io/hashicorp/ad"
      version = ">= 0.4.0"
    }
  }
}

provider "ad" {
  winrm_hostname = var.ad_server_hostname
  winrm_username = var.ad_bind_username
  winrm_password = var.ad_bind_password
  winrm_port     = var.ad_winrm_port
  winrm_proto    = var.ad_winrm_proto
  winrm_insecure = var.ad_winrm_insecure
  krb_realm      = var.ad_krb_realm
  krb_conf       = var.ad_krb_conf
}
