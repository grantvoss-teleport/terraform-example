# ---------------------------------------------------------------------------
# AD group membership via LDAPS + Python
#
# Uses ldap3 (pure Python) over LDAPS port 636 to query AD group membership
# recursively, returning member UPNs as a comma-separated string.
#
# Requirements on the Terraform runner:
#   /opt/homebrew/bin/python3 with ldap3 + pycryptodome:
#   /opt/homebrew/bin/python3 -m pip install ldap3 pycryptodome --break-system-packages
#
# Input:  { server, username, password, group_name }
# Output: { "upns": "user1@corp.com,user2@corp.com" }
# ---------------------------------------------------------------------------

data "external" "ad_group_members" {
  for_each = {
    for k, v in var.role_sets : k => v
    if v.ad_group_name != ""
  }

  program = [
    "/opt/homebrew/bin/python3",
    "${path.module}/scripts/get_ad_group_members.py"
  ]

  query = {
    server     = var.ad_server_hostname
    username   = var.ad_bind_username
    password   = var.ad_bind_password
    group_name = each.value.ad_group_name
  }
}
