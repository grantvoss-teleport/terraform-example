output "role_set_names" {
  description = "Names of all created roles per set"
  value = {
    for suffix in keys(var.role_sets) : suffix => {
      access    = teleport_role.access[suffix].metadata.name
      requester = teleport_role.requester[suffix].metadata.name
      reviewer  = teleport_role.reviewer[suffix].metadata.name
      acl       = teleport_access_list.exception_role[suffix].header.metadata.name
    }
  }
}

output "acl_member_usernames" {
  description = "All unique Teleport usernames created across all role sets"
  value       = [for u in teleport_user.acl_members : u.metadata.name]
}
