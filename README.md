# terraform-example

Terraform module for managing Teleport Access Control resources — roles, reviewers, requesters, and Access Lists — driven entirely by a single `role_sets` map variable. Adding a new access group requires only a new entry in that map.

## Requirements

| Tool | Version |
|---|---|
| Teleport cluster | >= 18.7.3 |
| Terraform provider | `= 18.7.3` (pinned) |
| Terraform CLI | >= 1.0.0 |

## Resources created per role set

| Resource | Name pattern | Notes |
|---|---|---|
| `teleport_role` (access) | `{prefix}-access-{suffix}` | SSH to nodes matching `node_label_value` |
| `teleport_role` (requester) | `{prefix}-requester-{suffix}` | Allows raising access requests |
| `teleport_role` (reviewer) | `{prefix}-reviewer-exception-{suffix}` | Scoped review via `cmdb_role_acl` trait predicate |
| `teleport_access_list` | `{prefix}-acl-exception-{suffix}` | Parent ACL, `type=static` |
| `teleport_access_list_member` (nested list) | `exception_users` as child | Nests pre-existing list under each parent ACL |
| `teleport_access_list_member` (users) | one per `local_acl_members` entry | Added to parent ACL |
| `teleport_user` | one per unique username across all sets | Local users only; SSO users excluded |

## Example — three role sets

```hcl
role_sets = {
  "db-admin" = {
    node_label_value  = "db_admin_prod"
    acl_title         = "DB Admin Prod"
    acl_description   = "Production database administrators"
    local_acl_members = []
    sso_acl_members = ["user+2@goteleport.com"] 
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
```

Produces resources named e.g. `ACME-access-db-admin`, `ACME-requester-k8s-ops`, `ACME-acl-exception-sec-break-glass`, etc.

## How it works

```
Requester user
  │  holds → ACME-requester-{suffix}
  │           └─ can request → ACME-access-{suffix}
  │
  └─ submits access request
           │
           ▼
  Reviewer user
    holds → ACME-reviewer-exception-{suffix}
             └─ can review if trait cmdb_role_acl contains node_label_value
                           │
                           ▼
                 ACME-access-{suffix} granted (max 8h)
                   └─ SSH to nodes where {node_label_key}={node_label_value}
                      as root or ubuntu

ACL hierarchy (repeated per role set):
  ACME-acl-exception-{suffix}   (parent — Terraform managed, type=static)
  ├── exception_users             (child list — pre-existing, nested only)
  └── members from local_acl_members
```

### Reviewer predicate

The reviewer role uses a trait predicate to scope who can approve requests:

```
contains(reviewer.traits["cmdb_role_acl"], "{node_label_value}")
```

The `cmdb_role_acl` trait is granted to ACL members via the parent ACL's `grants.traits` block, so any user added to a parent ACL can review requests for its corresponding access role.

### ACL nesting

The pre-existing `exception_users` list is nested as a child member (`membership_kind=2`) under every parent ACL created by this module. Terraform manages only the nesting relationship — it does not modify `exception_users` itself.

> **Note:** Terraform can only manage members of Access Lists with `type = "static"`. All parent ACLs are created as static. The pre-existing `exception_users` list must also be set to `type: static` via `tctl` if direct Terraform member management is needed in future.

### Role version

All roles use `version = "v8"`, which requires Teleport cluster >= 18 and Terraform provider >= 18. Role v8 adds Kubernetes CRD support but is fully compatible with SSH-only roles used here.

## Prerequisites

1. Teleport cluster running >= 18.7.3.
2. Run before every `terraform plan` or `terraform apply` session:
   ```sh
   eval "$(tctl terraform env)"
   ```
   Creates a short-lived bot identity (valid 1h) and sets `TF_TELEPORT_IDENTITY_FILE_PATH` automatically. Re-run if the session expires.
3. The `terraform-provider` preset role must be present in the cluster (it is by default). Required verbs: `read`, `list`, `create`, `update`, `delete` on `access_list`, `role`, and `user` resources.

## Usage

```sh
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set teleport_addr and define your role_sets

eval "$(tctl terraform env)"
terraform init
terraform plan
terraform apply
```

## Key variables

| Variable | Default | Description |
|---|---|---|
| `teleport_addr` | — | Proxy address, e.g. `cluster.teleport.sh:443` |
| `role_prefix` | `ACME` | Prefix for all role and ACL names |
| `node_label_key` | `cmdb_role` | Node label key used to scope all access roles |
| `ssh_logins` | `["root", "ubuntu"]` | OS logins granted by all access roles |
| `request_max_duration` | `8h0m0s` | Max duration of a granted access request |
| `approval_threshold` | `1` | Reviewers required to approve a request |
| `access_list_owner` | — | Teleport username of the ACL owner |
| `exception_users_acl_name` | *(UUID)* | Metadata name of the pre-existing `exception_users` ACL to nest under each parent |
| `extra_granted_roles` | `[]` | **Testing only** — extra roles granted by all ACLs |
| `role_sets` | *(see variables.tf)* | Map of suffix → role set config. Each entry produces a full set of roles and an ACL. |

### `role_sets` object schema

| Field | Type | Description |
|---|---|---|
| `node_label_value` | `string` | Value of `node_label_key` on target nodes |
| `acl_title` | `string` | Human-readable title for the Access List |
| `acl_description` | `string` | Optional description |
| `local_acl_members` | `list(string)` | Local Teleport usernames to create and add to this ACL |

## Adding a new role set

Add an entry to `role_sets` in `terraform.tfvars` and run `terraform apply`. No other changes needed.

```hcl
role_sets = {
  # ... existing sets ...
  "new-team" = {
    node_label_value  = "new_team_label"
    acl_title         = "New Team Access"
    acl_description   = "Access for the new team"
    local_acl_members = ["newuser@example.com"]
  }
}
```

## Removing a role set

Remove the entry from `role_sets` in `terraform.tfvars` and run `terraform apply`. Terraform will destroy all associated roles, ACL, and memberships for that set.

## SSO users

Do not add SSO-provisioned users to `local_acl_members` — they are managed by your IdP connector and do not need a `teleport_user` resource. Manage their ACL membership via IdP group mappings or add them to the Access List manually in the Teleport UI.

## Known provider quirks (v18.7.3)

| Field | Behaviour | Workaround |
|---|---|---|
| `spec.owners[].description` | Provider errors if set to `""` | Omit the field entirely |
| `spec.joined` on `teleport_access_list_member` | Provider overwrites with server timestamp | Omit the field |
| `spec.expires` on `teleport_access_list_member` | Provider drops zero value after apply | Omit the field |
