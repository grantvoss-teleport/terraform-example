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

  # Flatten ALL members (local + sso) across all role sets into a unique map
  # keyed by "suffix/username" — used to create teleport_access_list_member resources.
  all_members_flat = {
    for pair in flatten([
      for suffix, rs in var.role_sets : [
        for user in concat(rs.local_acl_members, rs.sso_acl_members) : {
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
