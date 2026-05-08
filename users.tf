# ---------------------------------------------------------------------------
# Local users
# One teleport_user per entry in var.local_acl_members.
# The user is given the requester and reviewer roles so they can both
# raise and review access requests. The ACL grants the cmdb_role_acl
# trait which the reviewer predicate checks at review time.
# ---------------------------------------------------------------------------
resource "teleport_user" "acl_members" {
  for_each = toset(var.local_acl_members)

  version = "v2"

  metadata = {
    name = each.value
  }

  spec = {
    roles = [
      teleport_role.requester.metadata.name,
      teleport_role.reviewer.metadata.name,
    ]
    traits = {
      # Populated here for local users; SSO users receive this via their IdP
      (local.acl_trait_key) = [local.acl_trait_value]
    }
  }

  depends_on = [
    teleport_role.requester,
    teleport_role.reviewer,
  ]
}
