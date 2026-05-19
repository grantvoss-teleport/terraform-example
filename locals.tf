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
  # The external data source runs scripts/get_ad_group_members.ps1 over WinRM
  # once per role_set.  The script returns a comma-separated string of UPNs
  # (e.g. "jane.doe@corp.example.com,john.smith@corp.example.com") under the
  # key "upns".  We split that back into a list here.
  # UPNs are used — never SAMAccountNames — because they must exactly match
  # the SSO identity Teleport receives from the IdP at login time.
  # ---------------------------------------------------------------------------
  ad_sourced_members = {
    for k, ext in data.external.ad_group_members :
    k => [
      for upn in split(",", ext.result["upns"]) : upn
      if upn != ""
    ]
  }

  # ---------------------------------------------------------------------------
  # Effective SSO members per role set:
  # - If ad_group_name is set  → UPNs from AD (ignores sso_acl_members)
  # - Otherwise                → explicit sso_acl_members list
  # ---------------------------------------------------------------------------
  effective_sso_members = {
    for k, rs in var.role_sets :
    k => rs.ad_group_name != "" ? local.ad_sourced_members[k] : rs.sso_acl_members
  }

  # ---------------------------------------------------------------------------
  # Flatten ALL members across all role sets into a unique map keyed by
  # "suffix/username".  Each entry carries a membership_kind so the ACL
  # resource knows whether to treat the user as an SSO identity or a local
  # Teleport user:
  #   0 = MEMBERSHIP_KIND_UNSPECIFIED (Teleport defaults this to SSO)
  #   1 = MEMBERSHIP_KIND_USER        (local Teleport user)
  #
  # AD-sourced and explicit sso_acl_members both use kind 0 so Teleport
  # matches them against the SSO identity (UPN) rather than expecting a
  # pre-created local account.
  # ---------------------------------------------------------------------------
  all_members_flat = {
    for pair in flatten([
      for suffix, rs in var.role_sets : concat(
        # SSO / AD members — kind 0
        [
          for user in local.effective_sso_members[suffix] : {
            key             = "${suffix}/${user}"
            suffix          = suffix
            user            = user
            membership_kind = 0
          }
        ],
        # Local Teleport users — kind 1
        [
          for user in rs.local_acl_members : {
            key             = "${suffix}/${user}"
            suffix          = suffix
            user            = user
            membership_kind = 1
          }
        ]
      )
    ]) : pair.key => pair
  }

  # Only local (non-SSO) users — for teleport_user resource creation
  unique_users = toset(flatten([
    for rs in var.role_sets : rs.local_acl_members
  ]))
}
