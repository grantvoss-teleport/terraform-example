#!/usr/bin/env pwsh
# -----------------------------------------------------------------------------
# get_ad_group_members.ps1
#
# Called by Terraform's external data source once per role_set that has a
# non-empty ad_group_name.  Receives a JSON object on stdin and returns a
# JSON object on stdout — both required by the external provider contract.
#
# Input JSON (from Terraform query block):
#   {
#     "server":     "ad.corp.example.com",
#     "username":   "svc-terraform@corp.example.com",
#     "password":   "...",
#     "group_name": "GRP-Teleport-DB-Admin"
#   }
#
# Output JSON (returned to Terraform — must be flat map of string→string):
#   {
#     "upns": "jane.doe@corp.example.com,john.smith@corp.example.com"
#   }
#
# Requirements on the Terraform runner:
#   - PowerShell 7+ (pwsh) installed
#   - Network access to the AD server on WinRM port (default 5985/HTTP or
#     5986/HTTPS).  Adjust New-PSSession parameters below to match your env.
# -----------------------------------------------------------------------------

$ErrorActionPreference = "Stop"

# Read and parse the JSON query from stdin
$raw   = [Console]::In.ReadToEnd()
$query = $raw | ConvertFrom-Json

$server    = $query.server
$username  = $query.username
$password  = $query.password | ConvertTo-SecureString -AsPlainText -Force
$groupName = $query.group_name

$cred = New-Object System.Management.Automation.PSCredential($username, $password)

# Open a WinRM session to the AD server.
# Adjust -Authentication to Kerberos if your environment requires it.
$sessionParams = @{
    ComputerName   = $server
    Credential     = $cred
    Authentication = "Negotiate"
}
$session = New-PSSession @sessionParams

try {
    $upns = Invoke-Command -Session $session -ScriptBlock {
        param($group)
        Import-Module ActiveDirectory -ErrorAction Stop

        # Get all members recursively, filter to user objects only,
        # then fetch the full user object to retrieve UserPrincipalName.
        Get-ADGroupMember -Identity $group -Recursive |
            Where-Object { $_.objectClass -eq "user" } |
            ForEach-Object {
                (Get-ADUser -Identity $_.SamAccountName `
                            -Properties UserPrincipalName).UserPrincipalName
            } |
            Where-Object { $_ -ne $null -and $_ -ne "" }
    } -ArgumentList $groupName
} finally {
    Remove-PSSession $session
}

# Return flat JSON — external data source requires map(string)
$result = @{
    upns = if ($upns) { $upns -join "," } else { "" }
}

Write-Output ($result | ConvertTo-Json -Compress)
