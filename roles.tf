# ---------------------------------------------------------------------------
# 1. Access role — grants SSH access to labelled nodes
# ---------------------------------------------------------------------------
resource "teleport_role" "access" {
  version = "v8"

  metadata = {
    name = local.access_role_name
  }

  spec = {
    allow = {
      logins = var.ssh_logins
      node_labels = {
        (var.node_label_key) = [var.node_label_value]
      }
    }

    deny = {}

    options = {
      cert_format               = local.common_options.cert_format
      create_db_user            = local.common_options.create_db_user
      create_desktop_user       = local.common_options.create_desktop_user
      desktop_clipboard         = local.common_options.desktop_clipboard
      desktop_directory_sharing = local.common_options.desktop_directory_sharing
      enhanced_recording        = local.common_options.enhanced_recording
      forward_agent             = local.common_options.forward_agent
      max_session_ttl           = local.common_options.max_session_ttl
      pin_source_ip             = local.common_options.pin_source_ip
      record_session = {
        default = local.common_options.record_session.default
        desktop = local.common_options.record_session.desktop
      }
      ssh_file_copy = local.common_options.ssh_file_copy
    }
  }
}

# ---------------------------------------------------------------------------
# 2. Requester role — allows users to request the access role
# ---------------------------------------------------------------------------
resource "teleport_role" "requester" {
  version = "v8"

  metadata = {
    name = local.requester_role_name
  }

  spec = {
    allow = {
      request = {
        search_as_roles = [teleport_role.access.metadata.name]
        max_duration    = var.request_max_duration
        thresholds = [
          {
            approve = var.approval_threshold
            deny    = var.denial_threshold
          }
        ]
      }
    }

    deny = {}

    options = {
      cert_format               = local.common_options.cert_format
      create_db_user            = local.common_options.create_db_user
      create_desktop_user       = local.common_options.create_desktop_user
      desktop_clipboard         = local.common_options.desktop_clipboard
      desktop_directory_sharing = local.common_options.desktop_directory_sharing
      enhanced_recording        = local.common_options.enhanced_recording
      forward_agent             = local.common_options.forward_agent
      max_session_ttl           = local.common_options.max_session_ttl
      pin_source_ip             = local.common_options.pin_source_ip
      record_session = {
        default = local.common_options.record_session.default
        desktop = local.common_options.record_session.desktop
      }
      ssh_file_copy = local.common_options.ssh_file_copy
    }
  }

  depends_on = [teleport_role.access]
}

# ---------------------------------------------------------------------------
# 3. Reviewer role — allows reviewing requests for the access role,
#    scoped to users whose cmdb_role_acl trait contains the target value
# ---------------------------------------------------------------------------
resource "teleport_role" "reviewer" {
  version = "v8"

  metadata = {
    name = local.reviewer_role_name
  }

  spec = {
    allow = {
      review_requests = {
        preview_as_roles = [teleport_role.access.metadata.name]
        roles            = [teleport_role.access.metadata.name]
        where            = "contains(reviewer.traits[\"${local.acl_trait_key}\"], \"${local.acl_trait_value}\")"
      }
    }

    deny = {}

    options = {
      cert_format               = local.common_options.cert_format
      create_db_user            = local.common_options.create_db_user
      create_desktop_user       = local.common_options.create_desktop_user
      desktop_clipboard         = local.common_options.desktop_clipboard
      desktop_directory_sharing = local.common_options.desktop_directory_sharing
      enhanced_recording        = local.common_options.enhanced_recording
      forward_agent             = local.common_options.forward_agent
      max_session_ttl           = local.common_options.max_session_ttl
      pin_source_ip             = local.common_options.pin_source_ip
      record_session = {
        default = local.common_options.record_session.default
        desktop = local.common_options.record_session.desktop
      }
      ssh_file_copy = local.common_options.ssh_file_copy
    }
  }

  depends_on = [teleport_role.access]
}
