output "access_role_name" {
  description = "Name of the created access role"
  value       = teleport_role.access.metadata.name
}

output "requester_role_name" {
  description = "Name of the created requester role"
  value       = teleport_role.requester.metadata.name
}

output "reviewer_role_name" {
  description = "Name of the created reviewer role"
  value       = teleport_role.reviewer.metadata.name
}

output "access_list_name" {
  description = "Name of the created Access List"
  value       = teleport_access_list.exception_role.header.metadata.name
}

output "acl_member_usernames" {
  description = "Teleport usernames added to the Access List"
  value       = [for u in teleport_user.acl_members : u.metadata.name]
}
