variable "teleport_addr" {
  type        = string
  description = "Teleport proxy/auth address, e.g. teleport.example.com:443"
}

variable "teleport_identity_file" {
  type        = string
  description = "Path to the Teleport identity file. Leave unset for local dev and use eval \"$(tctl terraform env)\" instead."
  default     = ""
}

# ---------------------------------------------------------------------------
# Access role name prefix (e.g. "coupang" → produces coupang-access-1, etc.)
# ---------------------------------------------------------------------------
variable "role_prefix" {
  type        = string
  description = "Short prefix used to namespace all role and ACL names"
  default     = "coupang"
}

variable "role_suffix" {
  type        = string
  description = "Numeric or env suffix appended to each role name"
  default     = "1"
}

# ---------------------------------------------------------------------------
# Node targeting
# ---------------------------------------------------------------------------
variable "node_label_key" {
  type        = string
  description = "Node label key used to scope the access role"
  default     = "cmdb_role"
}

variable "node_label_value" {
  type        = string
  description = "Node label value used to scope the access role"
  default     = "exception_role_1"
}

variable "ssh_logins" {
  type        = list(string)
  description = "OS logins the access role is allowed to use"
  default     = ["root", "ubuntu"]
}

# ---------------------------------------------------------------------------
# Access request settings
# ---------------------------------------------------------------------------
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

variable "exception_users_acl_name" {
  type        = string
  description = "Metadata name (UUID) of the pre-existing exception_users Access List"
  default     = "38a5ad8f-7646-4f87-8d6f-ae6020270f70"
}

# ---------------------------------------------------------------------------
# Access List / ACL
# ---------------------------------------------------------------------------
variable "access_list_title" {
  type        = string
  description = "Human-readable title for the Access List"
  default     = "Exception_role_1"
}

variable "access_list_description" {
  type        = string
  description = "Optional description for the Access List"
  default     = ""
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

variable "access_list_owner" {
  type        = string
  description = "Teleport username of the Access List owner"
  default     = "noam.zimet@goteleport.com"
}

# ---------------------------------------------------------------------------
# ACL members — local Teleport users to create and add to the Access List
# ---------------------------------------------------------------------------
variable "local_acl_members" {
  type        = list(string)
  description = "Local Teleport usernames that will be created and added to the Access List"
  default     = ["grant.voss@goteleport.com"]
}

# ---------------------------------------------------------------------------
# Additional roles granted by the Access List (beyond the three managed here)
# ---------------------------------------------------------------------------
variable "extra_granted_roles" {
  type        = list(string)
  description = <<-EOT
    Additional pre-existing roles to include in the Access List grants.
    Intended for testing only (e.g. ["auditor", "editor"]).
    Leave empty for production deployments.
  EOT
  default     = []
}
