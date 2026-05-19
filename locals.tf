locals {
  acl_trait_key = "cmdb_role_acl"

  # Shared role options block — applied identically to all roles
  common_options = {
    cert_format               = "standard"
    create_db_user            = false
    create_desktop_user       = false
    desktop_clipboard         = true
    desktop_directory_sharing = true
    enhanced_recording        = ["command", "network"]
    forward_agent             = false
    max_session_ttl           = var.max_session_ttl
    pin_source_ip             = false
    record_session = {
      default = "best_effort"
      desktop = true
    }
    ssh_file_copy = true
  }

  # ---------------------------------------------------------------------------
  # AD-sourced members
  # For each role_set that has a non-empty ad_group_name, collect the UPNs
  # (userPrincipalName) of every AD group member returned by the data source.
  # The hashicorp/ad provider exposes member DNs in
  # data.ad_group_membership.<key>.group_members as a list of objects with a
  # `dn` attribute; we map that to the `user_principal_name` attribute.
  # ---------------------------------------------------------------------------
  ad_sourced_members = {
    for k, gm in data.ad_group_membership.role_set_members :
    k => [
      for member in gm.group_members : member.user_principal_name
      if member.user_principal_name != null && member.user_principal_name != ""
    ]
  }

  # ---------------------------------------------------------------------------
  # Effective SSO members per role set:
  # - If ad_group_name is set  → use the AD-sourced list (ignores sso_acl_members)
  # - Otherwise                → fall back to the explicit sso_acl_members list
  # ---------------------------------------------------------------------------
  effective_sso_members = {
    for k, rs in var.role_sets :
    k => rs.ad_group_name != "" ? local.ad_sourced_members[k] : rs.sso_acl_members
  }

  # ---------------------------------------------------------------------------
  # Flatten ALL members (local + effective SSO) across all role sets into a
  # unique map keyed by "suffix/username" — used to create
  # teleport_access_list_member resources.
  # ---------------------------------------------------------------------------
  all_members_flat = {
    for pair in flatten([
      for suffix, rs in var.role_sets : [
        for user in concat(rs.local_acl_members, local.effective_sso_members[suffix]) : {
          key    = "${suffix}/${user}"
          suffix = suffix
          user   = user
        }
      ]
    ]) : pair.key => pair
  }

  # Only local (non-SSO) users — for teleport_user creation
  unique_users = toset(flatten([
    for rs in var.role_sets : rs.local_acl_members
  ]))
}
