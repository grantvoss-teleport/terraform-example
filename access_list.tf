# ---------------------------------------------------------------------------
# Reference to the pre-existing exception_users Access List
# ---------------------------------------------------------------------------
data "teleport_access_list" "exception_users" {
  header = {
    version = "v1"
    metadata = {
      name = var.exception_users_acl_name
    }
  }
}

# ---------------------------------------------------------------------------
# Access List
# Membership grants: requester role, reviewer role, the cmdb_role_acl trait,
# plus any extra roles (auditor, editor) passed in via variables.
# ---------------------------------------------------------------------------
resource "teleport_access_list" "exception_role" {
  header = {
    version = "v1"
    metadata = {
      name = "${var.role_prefix}-acl-exception-${var.role_suffix}"
    }
  }

  spec = {
    title       = var.access_list_title
    description = var.access_list_description
    type        = "static"

    owners = [
      {
        name = var.access_list_owner
      }
    ]

    # No prerequisite roles/traits needed to become a member
    membership_requires = {
      roles  = []
      traits = []
    }

    ownership_requires = {
      roles  = []
      traits = []
    }

    grants = {
      roles = concat(
        var.extra_granted_roles,
        [
          teleport_role.requester.metadata.name,
          teleport_role.reviewer.metadata.name,
        ]
      )
      traits = [
        {
          key    = local.acl_trait_key
          values = [local.acl_trait_value]
        }
      ]
    }

    owner_grants = {
      roles  = []
      traits = []
    }

    audit = {
      next_audit_date = var.audit_next_date
      notifications = {
        start = "336h0m0s" # 14-day heads-up, matching source config
      }
      recurrence = {
        frequency    = var.audit_frequency_months
        day_of_month = var.audit_day_of_month
      }
    }
  }

  depends_on = [
    teleport_role.requester,
    teleport_role.reviewer,
  ]
}

# ---------------------------------------------------------------------------
# Access List members — one resource per local user
# ---------------------------------------------------------------------------
resource "teleport_access_list_member" "acl_members" {
  for_each = toset(var.local_acl_members)

  header = {
    version = "v1"
    metadata = {
      name = each.value
    }
  }

  spec = {
    access_list     = teleport_access_list.exception_role.id
    name            = each.value
    membership_kind = 1 # 1 = MEMBERSHIP_KIND_USER
  }

  depends_on = [
    teleport_access_list.exception_role,
    teleport_user.acl_members,
  ]
}

# ---------------------------------------------------------------------------
# Nest exception_users as a child list member of the new ACL
# (new ACL is the parent; exception_users inherits its grants)
# ---------------------------------------------------------------------------
resource "teleport_access_list_member" "exception_users_nested" {
  header = {
    version = "v1"
    metadata = {
      name = data.teleport_access_list.exception_users.id
    }
  }

  spec = {
    access_list     = teleport_access_list.exception_role.id
    membership_kind = 2 # 2 = MEMBERSHIP_KIND_LIST
  }

  depends_on = [teleport_access_list.exception_role]
}
