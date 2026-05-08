# terraform-example

Terraform module for managing Teleport Access Control resources for Coupang.

## Requirements

| Tool | Version |
|---|---|
| Teleport cluster | 18.7.3 |
| Terraform provider | `= 18.7.3` (pinned) |
| Terraform CLI | >= 1.0.0 |

## Resources created

| Resource | Name pattern | Notes |
|---|---|---|
| `teleport_role` (access) | `{prefix}-access-{suffix}` | SSH to labelled nodes |
| `teleport_role` (requester) | `{prefix}-requester-{suffix}` | Allows raising access requests |
| `teleport_role` (reviewer) | `{prefix}-reviewer-exception-{suffix}` | Scoped review via trait predicate |
| `teleport_access_list` | `{prefix}-acl-exception-{suffix}` | Parent ACL, type=static |
| `teleport_access_list_member` (nested list) | `exception_users` as child | Nests pre-existing list under parent |
| `teleport_access_list_member` (users) | one per `local_acl_members` entry | Added to parent ACL |
| `teleport_user` | one per `local_acl_members` entry | Local users only |

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
                 coupang-access-1 granted (max 8h)
                   └─ SSH to nodes where cmdb_role=exception_role_1
                      as root or ubuntu

ACL hierarchy:
  coupang-acl-exception-1  (parent — managed by Terraform, type=static)
  ├── exception_users       (child list, membership_kind=2 — pre-existing, nested only)
  └── grant.voss+1@...      (user members from local_acl_members, membership_kind=1)
```

### Role version

All roles use `version = "v8"` which requires Teleport cluster >= 18 and
Terraform provider >= 18. Role v8 adds Kubernetes CRD support but is fully
compatible with SSH-only roles used here.

### Reviewer predicate

The reviewer role uses a trait predicate to scope who can approve requests:

```
contains(reviewer.traits["cmdb_role_acl"], "exception_role_1")
```

The `cmdb_role_acl` trait is granted to ACL members via the parent ACL's
`grants.traits` block, so any user added to `coupang-acl-exception-1` can
review requests for `coupang-access-1`.

### ACL nesting

The pre-existing `exception_users` list (`exception_users_acl_name` variable)
is nested as a child member of the new parent ACL. Terraform manages only the
nesting relationship — it does not modify `exception_users` itself.

Note: Terraform can only manage members of Access Lists with `type = "static"`.
The parent ACL is created as static. The pre-existing `exception_users` list
must also be set to `type: static` via `tctl` if direct member management is
needed in future.

## Prerequisites

1. Teleport cluster running v18.7.3.
2. Run the following before `terraform plan` or `terraform apply`:
   ```sh
   eval "$(tctl terraform env)"
   ```
   This creates a short-lived bot identity (valid 1h) and sets
   `TF_TELEPORT_IDENTITY_FILE_PATH` automatically. Re-run if the session expires.
3. The `terraform-provider` preset role must be present in the cluster
   (it is by default). It grants full CRUD on roles, users, and access lists.

## Usage

```sh
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — at minimum set teleport_addr

eval "$(tctl terraform env)"
terraform init
terraform plan
terraform apply
```

## Key variables

| Variable | Default | Description |
|---|---|---|
| `teleport_addr` | — | Proxy address, e.g. `cluster.teleport.sh:443` |
| `role_prefix` | `coupang` | Prefix for all role/ACL names |
| `role_suffix` | `1` | Suffix for all role/ACL names |
| `node_label_key` | `cmdb_role` | Node label key for access scoping |
| `node_label_value` | `exception_role_1` | Node label value for access scoping |
| `ssh_logins` | `["root", "ubuntu"]` | OS logins granted by access role |
| `request_max_duration` | `8h0m0s` | Max duration of a granted access request |
| `approval_threshold` | `1` | Reviewers required to approve |
| `local_acl_members` | `[]` | Local Teleport users to create and add to ACL |
| `exception_users_acl_name` | *(UUID)* | Metadata name of pre-existing `exception_users` ACL |
| `extra_granted_roles` | `[]` | Testing only — extra roles granted by ACL |

## Adding more ACL members

Append usernames to `local_acl_members` in `terraform.tfvars` and re-run
`terraform apply`. For SSO users who are provisioned by your IdP, do not add
a corresponding `teleport_user` resource — instead manage their ACL membership
separately or via IdP group mappings.

## Scaling to multiple access roles

Duplicate the pattern with a new `role_suffix` (e.g. `"2"`) and a new
`node_label_value` to target a different set of nodes. Or convert this into a
reusable child module and call it once per access role.

## Known provider quirks (v18.7.3)

- `spec.owners[].description` must be omitted (not set to `""`) or the provider
  returns an inconsistent result error after apply.
- `spec.joined` and `spec.expires` on `teleport_access_list_member` must be
  omitted — the provider sets these server-side and will error if they are
  specified with static values.
