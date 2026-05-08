# ---------------------------------------------------------------------------
# Local users — one per unique username across all role sets
# ---------------------------------------------------------------------------
resource "teleport_user" "acl_members" {
  for_each = local.unique_users

  version = "v2"

  metadata = {
    name = each.value
  }

  spec = {
    roles = flatten([
      for suffix, rs in var.role_sets :
      contains(rs.local_acl_members, each.value) ? [
        teleport_role.requester[suffix].metadata.name,
        teleport_role.reviewer[suffix].metadata.name,
      ] : []
    ])
    traits = {
      (local.acl_trait_key) = [
        for suffix, rs in var.role_sets :
        rs.node_label_value
        if contains(rs.local_acl_members, each.value)
      ]
    }
  }

  depends_on = [
    teleport_role.requester,
    teleport_role.reviewer,
  ]
}
