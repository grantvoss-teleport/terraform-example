#!/usr/bin/env pwsh
# -----------------------------------------------------------------------------
# get_ad_group_members.ps1
#
# Called by Terraform's external data source once per role_set that has a
# non-empty ad_group_name.  Connects to the AD server via WinRM HTTP (port
# 5985) using Negotiate authentication — no WSMan HTTPS or Kerberos required.
#
# Prerequisites on the Terraform runner (Mac):
#   - PowerShell 7+ (pwsh): brew install powershell
#   - MI engine for macOS (ships with pwsh 7 via OMI):
#       brew install openssl@1.1
#       Install-Module -Name PSWSMan; Install-WSMan  (run once as root)
#
# Prerequisites on the AD server (Windows Server 2025):
#   - WinRM HTTP listener on port 5985 (enabled by default on a DC)
#   - The service account must be in the local Remote Management Users group
#   - RSAT ActiveDirectory module available (default on a DC)
#
# Input JSON (from Terraform query block):
#   {
#     "server":     "adwest1.gvteleport.com",
#     "username":   "svc-terraform@corp.example.com",
#     "password":   "...",
#     "group_name": "GRP-Teleport-DB-Admin"
#   }
#
# Output JSON (flat map of string→string, required by external provider):
#   { "upns": "jane.doe@corp.example.com,john.smith@corp.example.com" }
# -----------------------------------------------------------------------------

$ErrorActionPreference = "Stop"

# Must be imported before New-PSSession on macOS to load the MI/OMI engine
Import-Module PSWSMan

$query     = [Console]::In.ReadToEnd() | ConvertFrom-Json
$server    = $query.server
$username  = $query.username
$password  = $query.password | ConvertTo-SecureString -AsPlainText -Force
$groupName = $query.group_name

$cred = New-Object System.Management.Automation.PSCredential($username, $password)

# Use HTTP (5985) with Negotiate auth — works from macOS with PSWSMan installed
$sessionParams = @{
    ComputerName   = $server
    Credential     = $cred
    Authentication = "Negotiate"
    Port           = 5985
    UseSSL         = $false
}

$session = New-PSSession @sessionParams

try {
    $upns = Invoke-Command -Session $session -ScriptBlock {
        param($group)
        Import-Module ActiveDirectory -ErrorAction Stop
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

$result = @{
    upns = if ($upns) { $upns -join "," } else { "" }
}

Write-Output ($result | ConvertTo-Json -Compress)
