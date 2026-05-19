# ---------------------------------------------------------------------------
# AD group membership via external data source + PowerShell
#
# The hashicorp/ad provider has no data source for reading group membership
# (ad_group_membership is a managed resource for writing membership, not
# reading it).  Instead we invoke a PowerShell script over WinRM once per
# role_set that has a non-empty ad_group_name.
#
# The script returns a flat JSON object:
#   { "upns": "jane.doe@corp.example.com,john.smith@corp.example.com" }
#
# locals.tf splits the comma-separated string back into a list of UPNs.
# ---------------------------------------------------------------------------

data "external" "ad_group_members" {
  for_each = {
    for k, v in var.role_sets : k => v
    if v.ad_group_name != ""
  }

  program = [
    "pwsh", "-NonInteractive", "-NoProfile", "-File",
    "${path.module}/scripts/get_ad_group_members.ps1"
  ]

  query = {
    server     = var.ad_server_hostname
    username   = var.ad_bind_username
    password   = var.ad_bind_password
    group_name = each.value.ad_group_name
  }
}
