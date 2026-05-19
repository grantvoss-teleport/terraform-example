# ---------------------------------------------------------------------------
# Active Directory data sources
# Look up each AD group listed under ad_group_name in var.role_sets,
# then read its members so Teleport ACLs are driven by AD group membership.
# ---------------------------------------------------------------------------

# Fetch the AD group object for every role set that has an ad_group_name set.
data "ad_group" "role_set_groups" {
  for_each = {
    for k, v in var.role_sets : k => v
    if v.ad_group_name != ""
  }

  group_id = each.value.ad_group_name
}

# Enumerate the members of each AD group.
data "ad_group_membership" "role_set_members" {
  for_each = data.ad_group.role_set_groups

  group_id = each.value.id
}
