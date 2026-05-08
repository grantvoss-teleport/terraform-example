locals {
  access_role_name   = "${var.role_prefix}-access-${var.role_suffix}"
  requester_role_name = "${var.role_prefix}-requester-${var.role_suffix}"
  reviewer_role_name = "${var.role_prefix}-reviewer-exception-${var.role_suffix}"
  acl_trait_key      = "cmdb_role_acl"
  acl_trait_value    = var.node_label_value

  # Shared role options block — applied identically to all three roles
  common_options = {
    cert_format              = "standard"
    create_db_user           = false
    create_desktop_user      = false
    desktop_clipboard        = true
    desktop_directory_sharing = true
    enhanced_recording       = ["command", "network"]
    forward_agent            = false
    max_session_ttl          = var.max_session_ttl
    pin_source_ip            = false
    record_session = {
      default  = "best_effort"
      desktop  = true
    }
    ssh_file_copy = true
  }
}
