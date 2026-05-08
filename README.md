# terraform-example

Terraform module for managing Teleport Access Control resources for Coupang.

## Resources created

| Resource | Name pattern |
|---|---|
| `teleport_role` (access) | `{prefix}-access-{suffix}` |
| `teleport_role` (requester) | `{prefix}-requester-{suffix}` |
| `teleport_role` (reviewer) | `{prefix}-reviewer-exception-{suffix}` |
| `teleport_access_list` | `{prefix}-acl-exception-{suffix}` |
| `teleport_user` | one per entry in `local_acl_members` |
| `teleport_access_list_member` | one per entry in `local_acl_members` |

## How it works

```
Requester user
  │  holds → coupang-requester-1
  │           └─ can request → coupang-access-1
  │
  └─ submits access request
           │
           ▼
  Reviewer user
    holds → coupang-reviewer-exception-1
             └─ can review if trait cmdb_role_acl contains "exception_role_1"
                           │
                           ▼
                 coupang-access-1 granted (max 8 h)
                   └─ SSH to nodes where cmdb_role=exception_role_1
                      as root or ubuntu

Access List (coupang-acl-exception-1)
  owners   → noam.zimet@goteleport.com
  members  → grant.voss@goteleport.com (and any others in local_acl_members)
  grants   → requester role + reviewer role + cmdb_role_acl trait
             + auditor + editor (extra_granted_roles)
  audit    → every 6 months, 14-day notification window
```

## Prerequisites

1. Teleport cluster running v16+.
2. A Terraform identity file (see `teleport_identity_file` variable).
   Obtain with:
   ```sh
   eval "$(tctl terraform env)"
   # or
   tctl auth sign --user terraform --format=identity -o terraform-identity
   ```
3. The Terraform user/bot must have privileges to create roles, users, and
   access lists (typically the preset `editor` role or a scoped equivalent).

## Usage

```sh
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with real values

terraform init
terraform plan
terraform apply
```

## Adding more ACL members

Append usernames to `local_acl_members` in `terraform.tfvars` and re-run
`terraform apply`. For SSO users, add them to `local_acl_members` **without**
creating a `teleport_user` resource — SSO users are provisioned by your IdP
connector. To accommodate this, extract the user creation into a separate
`for_each` set that excludes SSO usernames, or manage SSO users' ACL
membership via your IdP group mappings.

## Scaling to multiple access roles

Copy the pattern: duplicate `roles.tf` variables/resources with a new
`role_suffix` (e.g. `"2"`), or convert this module into a reusable child
module and call it once per access role.
