# terraform-example

Terraform module for managing Teleport Access Control resources — roles, reviewers, requesters, and Access Lists — driven entirely by a single `role_sets` map variable. Member population is handled automatically by querying an Active Directory 2025 server via LDAPS; no comma-separated user lists are required. Adding a new access group requires only a new entry in `variables.tf`.

## Requirements

| Tool | Version |
|---|---|
| Teleport cluster | >= 18.7.3 |
| Teleport Terraform provider | `= 18.7.6` (pinned) |
| HashiCorp external Terraform provider | `>= 2.3.0` |
| Terraform CLI | >= 1.0.0 |
| Python 3 (Homebrew) | >= 3.12 |
| AD server | Windows Server 2025, LDAPS on port 636 |

## Python dependencies

The AD membership script requires two Python packages on the Terraform runner:

```sh
/opt/homebrew/bin/python3 -m pip install ldap3 pycryptodome --break-system-packages
```

## Providers

| Provider | Source | Purpose |
|---|---|---|
| `teleport` | `terraform.releases.teleport.dev/gravitational/teleport` | Manages roles, Access Lists, and members |
| `external` | `registry.terraform.io/hashicorp/external` | Runs the Python LDAPS script to resolve group membership |

## Resources created per role set

| Resource | Name pattern | Notes |
|---|---|---|
| `teleport_role` (access) | `{prefix}-access-{suffix}` | SSH to nodes matching `node_label_value` |
| `teleport_role` (requester) | `{prefix}-requester-{suffix}` | Allows raising access requests |
| `teleport_role` (reviewer) | `{prefix}-reviewer-exception-{suffix}` | Scoped review via `cmdb_role_acl` trait predicate |
| `teleport_access_list` | `{prefix}-acl-exception-{suffix}` | Parent ACL, `type=static` |
| `teleport_access_list_member` (nested list) | `exception_users` as child | Nests pre-existing list under each parent ACL |
| `teleport_access_list_member` (users) | one per resolved group member | SSO members from AD (kind=0) or local members (kind=1) |
| `teleport_user` | one per unique `local_acl_members` entry | Local users only; AD/SSO users do not get a local resource |


## How AD integration works

When `ad_group_name` is set on a role set, Terraform invokes `scripts/get_ad_group_members.py` via the `external` data source. The script:

1. Connects to the AD server over LDAPS (port 636) using NTLM auth.
2. Looks up the group by `sAMAccountName`.
3. Retrieves all members recursively using `LDAP_MATCHING_RULE_IN_CHAIN` (handles nested groups).
4. Returns each member's `userPrincipalName` (UPN).
5. Registers each UPN as an SSO member (`membership_kind = 0`) in the Teleport Access List.

The UPN is used — never the SAMAccountName — because it must exactly match the identity Teleport receives from the SSO/IdP at login time.

When `ad_group_name` is left empty (`""`), the role set falls back to the explicit `sso_acl_members` list.

```
Active Directory 2025
  └── AD Group (sAMAccountName = ad_group_name)
        ├── jane.doe@corp.example.com  (userPrincipalName)
        ├── john.smith@corp.example.com
        └── ...
              │
              │  scripts/get_ad_group_members.py over LDAPS:636
              ▼
  Teleport Access List  (ACME-acl-exception-{suffix})
        ├── jane.doe@corp.example.com   membership_kind=0  (SSO)
        ├── john.smith@corp.example.com membership_kind=0  (SSO)
        └── exception_users             membership_kind=2  (nested list)
```

## How access requests work

```
Requester user
  │  holds → ACME-requester-{suffix}
  │           └─ can request → ACME-access-{suffix}
  │
  └─ submits access request
           │
           ▼
  Reviewer user (member of ACME-acl-exception-{suffix} via AD group)
    holds → ACME-reviewer-exception-{suffix}
             └─ can review if trait cmdb_role_acl contains node_label_value
                           │
                           ▼
                 ACME-access-{suffix} granted (max 8h)
                   └─ SSH to nodes where {node_label_key}={node_label_value}
                      as root or ubuntu
```

### Reviewer predicate

The reviewer role uses a trait predicate to scope who can approve requests:

```
contains(reviewer.traits["cmdb_role_acl"], "{node_label_value}")
```

The `cmdb_role_acl` trait is granted to ACL members via the parent ACL's `grants.traits` block, so any user added to a parent ACL can review requests for its corresponding access role.

### ACL nesting

The pre-existing `exception_users` list is nested as a child member (`membership_kind=2`) under every parent ACL. Terraform manages only the nesting relationship — it does not modify `exception_users` itself.

> **Note:** Terraform can only manage members of Access Lists with `type = "static"`. All parent ACLs are created as static.


## Prerequisites

1. **Teleport cluster** running >= 18.7.3. The `terraform-provider` bot role must have these verbs on `access_list`, `role`, and `user` resources: `read`, `list`, `create`, `update`, `delete`. If missing, add them:
   ```sh
   tctl get role/terraform-provider -o yaml > terraform-provider-role.yaml
   # Add access_list to allow.rules, then:
   tctl create -f terraform-provider-role.yaml
   ```

2. **Teleport bot identity** — run before every `terraform plan` / `terraform apply` session:
   ```sh
   eval "$(tctl terraform env)"
   ```
   Creates a short-lived identity (valid 1h). Re-run if the session expires.

3. **AD service account** with LDAP read access. Supply credentials at runtime:
   ```sh
   export TF_VAR_ad_server_hostname="adwest1.corp.example.com"
   export TF_VAR_ad_bind_username="svc-terraform@corp.example.com"
   export TF_VAR_ad_bind_password="..."
   ```
   The username can be either `DOMAIN\user` or `user@domain.com` — the script converts UPN format automatically.

4. **LDAPS configured on the AD server** (port 636). See `docs/ad-dc-setup.md` for the full DC configuration runbook.

## Usage

```sh
export TF_VAR_ad_server_hostname="adwest1.corp.example.com"
export TF_VAR_ad_bind_username="svc-terraform@corp.example.com"
export TF_VAR_ad_bind_password="..."
eval "$(tctl terraform env)"
terraform init
terraform plan
terraform apply
```

## Key variables

### Teleport connection

| Variable | Default | Description |
|---|---|---|
| `teleport_addr` | `teleport.example.com:443` | Proxy address |
| `teleport_identity_file` | `""` | Path to identity file; leave unset when using `tctl terraform env` |
| `role_prefix` | `ACME` | Prefix for all role and ACL names |
| `node_label_key` | `cmdb_role` | Node label key used to scope all access roles |
| `ssh_logins` | `["root","ubuntu"]` | OS logins granted by all access roles |
| `max_session_ttl` | `30h0m0s` | Maximum certificate TTL |
| `request_max_duration` | `8h0m0s` | Max duration of a granted access request |
| `approval_threshold` | `1` | Reviewer approvals required |
| `denial_threshold` | `1` | Reviewer denials required |
| `access_list_owner` | `user@example.com` | Teleport username of the ACL owner |
| `exception_users_acl_name` | *(UUID)* | Metadata name of the pre-existing `exception_users` ACL |
| `extra_granted_roles` | `[]` | **Testing only** — extra roles granted by all ACLs |

### Active Directory connection

| Variable | Default | Description |
|---|---|---|
| `ad_server_hostname` | *(required)* | FQDN or IP of the AD 2025 server |
| `ad_bind_username` | *(required)* | Service account — UPN (`user@domain`) or `DOMAIN\user` format |
| `ad_bind_password` | *(required, sensitive)* | Service account password — use `TF_VAR_ad_bind_password` env var |

### `role_sets` map

Each key is a short suffix used in all resource names (e.g. `"db-admin"` → `ACME-acl-exception-db-admin`).

| Field | Type | Description |
|---|---|---|
| `node_label_value` | `string` | Value of `node_label_key` on target nodes |
| `acl_title` | `string` | Human-readable title for the Access List |
| `acl_description` | `string` | Description shown in the Teleport UI |
| `ad_group_name` | `string` | `sAMAccountName` of the AD group to look up. Set to `""` to use `sso_acl_members` instead |
| `local_acl_members` | `list(string)` | Local Teleport usernames — a `teleport_user` resource is created for each |
| `sso_acl_members` | `list(string)` | Explicit SSO user UPNs — only used when `ad_group_name` is `""` |


## Example — three role sets (AD-driven)

```hcl
role_sets = {
  "db-admin" = {
    node_label_value  = "db_admin_prod"
    acl_title         = "DB Admin Prod"
    acl_description   = "Production database administrators"
    ad_group_name     = "GRP-Teleport-DB-Admin"
    local_acl_members = []
    sso_acl_members   = []
  }
  "k8s-ops" = {
    node_label_value  = "k8s_ops_staging"
    acl_title         = "K8s Ops Staging"
    acl_description   = "Kubernetes operators for staging cluster"
    ad_group_name     = "GRP-Teleport-K8s-Ops"
    local_acl_members = []
    sso_acl_members   = []
  }
  "sec-break-glass" = {
    node_label_value  = "security_break_glass"
    acl_title         = "Security Break Glass"
    acl_description   = "Emergency break-glass access for security team"
    ad_group_name     = ""
    local_acl_members = []
    sso_acl_members   = ["admin@corp.example.com"]
  }
}
```

## Adding a new role set

1. Create the AD group in your directory (e.g. `GRP-Teleport-NewTeam`).
2. Add an entry to `role_sets` in `variables.tf`.
3. Run `terraform apply`. All roles, the ACL, and member resources are created automatically.

Adding or removing a user from the AD group and re-running `terraform apply` syncs membership to Teleport.

## Removing a role set

Remove the entry from `role_sets` in `variables.tf` and run `terraform apply`. Terraform destroys all associated roles, the ACL, and memberships.

## Membership kind reference

| Source | `membership_kind` | Teleport behaviour |
|---|---|---|
| AD group member (via `ad_group_name`) | `0` (SSO) | Matched against SSO/IdP identity at login; no local `teleport_user` created |
| Explicit `sso_acl_members` | `0` (SSO) | Same as above |
| `local_acl_members` | `1` (local user) | Requires a `teleport_user` resource; Terraform creates it automatically |
| Nested `exception_users` list | `2` (list) | Entire list nested as a child; managed separately |

## Known provider quirks (v18.7.6)

| Field | Behaviour | Workaround |
|---|---|---|
| `spec.owners[].description` | Provider errors if set to `""` | Omit the field entirely |
| `spec.joined` on `teleport_access_list_member` | Provider overwrites with server timestamp | Omit the field |
| `spec.expires` on `teleport_access_list_member` | Provider drops zero value after apply | Omit the field |
