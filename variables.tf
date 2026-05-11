variable "teleport_addr" {
  type        = string
  description = "Teleport proxy/auth address, e.g. teleport.example.com:443"
}

variable "teleport_identity_file" {
  type        = string
  description = "Path to the Teleport identity file. Leave unset for local dev and use eval \"$(tctl terraform env)\" instead."
  default     = ""
}

variable "role_prefix" {
  type        = string
  description = "Short prefix used to namespace all role and ACL names"
  default     = "ACME"
}

variable "node_label_key" {
  type        = string
  description = "Node label key used to scope access roles"
  default     = "cmdb_role"
}

variable "ssh_logins" {
  type        = list(string)
  description = "OS logins granted by all access roles"
  default     = ["root", "ubuntu"]
}

variable "max_session_ttl" {
  type        = string
  description = "Maximum certificate TTL for all roles"
  default     = "30h0m0s"
}

variable "request_max_duration" {
  type        = string
  description = "Maximum duration a granted access request remains valid"
  default     = "8h0m0s"
}

variable "approval_threshold" {
  type        = number
  description = "Number of reviewer approvals required to grant a request"
  default     = 1
}

variable "denial_threshold" {
  type        = number
  description = "Number of reviewer denials required to deny a request"
  default     = 1
}

variable "access_list_owner" {
  type        = string
  description = "Teleport username of the Access List owner"
  default     = "grant.voss@goteleport.com"
}

variable "audit_frequency_months" {
  type        = number
  description = "How often (in months) the Access List must be re-audited. Supported: 1, 3, 6, 12"
  default     = 6
}

variable "audit_day_of_month" {
  type        = number
  description = "Day of month audits are scheduled. Supported: 1, 15, 31"
  default     = 1
}

variable "audit_next_date" {
  type        = string
  description = "ISO-8601 datetime for the next scheduled audit"
  default     = "2026-12-05T08:00:00Z"
}

variable "exception_users_acl_name" {
  type        = string
  description = "Metadata name (UUID) of the pre-existing exception_users Access List"
  default     = "6fcd4bf0-1f79-4351-891e-2bdf29d6f5f9"
}

# ---------------------------------------------------------------------------
# Additional roles granted by all Access Lists (testing only)
# ---------------------------------------------------------------------------
variable "extra_granted_roles" {
  type        = list(string)
  description = <<-EOT
    Additional pre-existing roles to include in all Access List grants.
    Intended for testing only (e.g. ["auditor", "editor"]).
    Leave empty for production deployments.
  EOT
  default     = []
}

# ---------------------------------------------------------------------------
# Role sets — one entry per access role / ACL group
#
# Each key is the suffix used in resource names (e.g. "1" → ACME-access-1).
# Each value defines the node label value, ACL title, and members for that set.
# ---------------------------------------------------------------------------
variable "role_sets" {
  type = map(object({
    node_label_value  = string
    acl_title         = string
    acl_description   = string
    local_acl_members = list(string)
    sso_acl_members   = list(string)
  }))
  description = "Map of role set suffix → configuration. Each entry produces one full set of roles and an ACL."
  default = {
    "db-admin" = {
      node_label_value  = "db_admin_prod"
      acl_title         = "DB Admin Prod"
      acl_description   = "Production database administrators"
      local_acl_members = []
      sso_acl_members   = ["user+2@goteleport.com"]
    }
    "k8s-ops" = {
      node_label_value  = "k8s_ops_staging"
      acl_title         = "K8s Ops Staging"
      acl_description   = "Kubernetes operators for staging cluster"
      local_acl_members = []
      sso_acl_members   = ["user+3@goteleport.com"]
    }
    "sec-break-glass" = {
      node_label_value  = "security_break_glass"
      acl_title         = "Security Break Glass"
      acl_description   = "Emergency break-glass access for security team"
      local_acl_members = []
      sso_acl_members   = ["user+2@goteleport.com", "user+4@goteleport.com"]
    }
  }
}
