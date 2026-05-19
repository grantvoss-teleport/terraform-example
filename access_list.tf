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
# Access Lists — one per role set
# ---------------------------------------------------------------------------
resource "teleport_access_list" "exception_role" {
  for_each = var.role_sets

  header = {
    version = "v1"
    metadata = {
      name = "${var.role_prefix}-acl-exception-${each.key}"
    }
  }

  spec = {
    title       = each.value.acl_title
    description = each.value.acl_description
    type        = "static"

    owners = [
      {
        name = var.access_list_owner
      }
    ]

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
          teleport_role.requester[each.key].metadata.name,
          teleport_role.reviewer[each.key].metadata.name,
        ]
      )
      traits = [
        {
          key    = local.acl_trait_key
          values = [each.value.node_label_value]
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
        start = "336h0m0s"
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
# ACL user members — one per (role set, user) pair
# membership_kind comes from the flat map:
#   0 = SSO / AD-sourced identity (matched by UPN at login time)
#   1 = local Teleport user (pre-created teleport_user resource)
# ---------------------------------------------------------------------------
resource "teleport_access_list_member" "acl_members" {
  for_each = local.all_members_flat

  header = {
    version = "v1"
    metadata = {
      name = each.value.user
    }
  }

  spec = {
    access_list     = teleport_access_list.exception_role[each.value.suffix].id
    name            = each.value.user
    membership_kind = each.value.membership_kind
  }

  depends_on = [
    teleport_access_list.exception_role,
  ]
}

# ---------------------------------------------------------------------------
# Nest exception_users as a child list under each parent ACL
# ---------------------------------------------------------------------------
resource "teleport_access_list_member" "exception_users_nested" {
  for_each = var.role_sets

  header = {
    version = "v1"
    metadata = {
      name = data.teleport_access_list.exception_users.id
    }
  }

  spec = {
    access_list     = teleport_access_list.exception_role[each.key].id
    membership_kind = 2 # MEMBERSHIP_KIND_LIST
  }

  depends_on = [teleport_access_list.exception_role]
}
