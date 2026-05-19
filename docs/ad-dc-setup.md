# AD Domain Controller Setup Runbook

Windows Server 2025 DC configuration for Teleport + Terraform LDAPS integration.
This runbook documents every step taken to get LDAPS working with a Let's Encrypt
certificate issued via win-acme and Route53 DNS-01 validation.

**Environment:**
- DC hostname: `EC2AMAZ-BN6T5TL.adwest1.gvteleport.com`
- DC public DNS: `adwest1.gvteleport.com` (Route53, publicly resolvable)
- Domain: `adwest1.gvteleport.com`
- OS: Windows Server 2025 (EC2)
- IAM role attached to EC2 instance: `grantvoss-certbot-role-1`

---

## 1. Issue a TLS certificate via win-acme + Let's Encrypt (DNS-01 / Route53)

### Why
LDAPS on Windows Server 2025 requires a valid TLS certificate bound to the DC.
The DC is publicly accessible at `adwest1.gvteleport.com` so Let's Encrypt DNS-01
via Route53 is the cleanest approach — no IIS, no CA infrastructure needed.

### Download win-acme and the Route53 plugin

```powershell
# Run from an elevated PowerShell session on the DC
Invoke-WebRequest -Uri "https://github.com/win-acme/win-acme/releases/download/v2.2.9.1701/win-acme.v2.2.9.1701.x64.pluggable.zip" -OutFile wacs.zip
Expand-Archive wacs.zip -DestinationPath win-acme

Invoke-WebRequest -Uri "https://github.com/win-acme/win-acme/releases/download/v2.2.9.1701/plugin.validation.dns.route53.v2.2.9.1701.zip" -OutFile route53-plugin.zip
Expand-Archive route53-plugin.zip -DestinationPath win-acme

# Unblock DLLs so .NET will load them
Get-ChildItem win-acme\*.dll | Unblock-File
```

### Configure win-acme settings

Edit `win-acme\settings.json` and set both of these under `Store.CertificateStore`:

```json
"CertificateStore": {
  "PrivateKeyExportable": true,
  "UseNextGenerationCryptoApi": true
}
```

`PrivateKeyExportable` is required so you can re-import the cert with the correct
KSP provider. `UseNextGenerationCryptoApi` sets the target to Microsoft Software
Key Storage Provider, which NTDS on Server 2025 requires.

### Request the certificate

The EC2 instance has an IAM role with Route53 permissions, so no AWS credentials
are needed — win-acme uses the instance metadata service automatically:

```powershell
cd win-acme

# Issue cert with both the public DNS name AND the DC's internal FQDN as SANs.
# Both are required: adwest1.gvteleport.com for Let's Encrypt validation,
# EC2AMAZ-BN6T5TL.adwest1.gvteleport.com to match the DC's dNSHostName in AD.
.\wacs.exe `
  --source manual `
  --host "adwest1.gvteleport.com,EC2AMAZ-BN6T5TL.adwest1.gvteleport.com" `
  --validation route53 `
  --route53iamrole grantvoss-certbot-role-1 `
  --store certificatestore `
  --certificatestore My `
  --installation none `
  --accepttos `
  --emailaddress your-email@example.com
```

win-acme creates a Windows Scheduled Task for auto-renewal. After renewal the cert
must be re-imported with KSP and NTDS restarted — see section 3 for the renewal
hook script.

---

## 2. Re-import the certificate with the correct KSP provider

Windows Server 2025 NTDS requires the private key to be in the
`Microsoft Software Key Storage Provider` (KSP / CNG), not the legacy
`Microsoft Enhanced Cryptographic Provider` (CAPI). win-acme imports with CAPI
by default even with `UseNextGenerationCryptoApi: true`, so a manual re-import
is required after issuance.

```powershell
# Get the thumbprint of the newly issued cert
$thumb = (Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*adwest1*" }).Thumbprint
Write-Host "Thumbprint: $thumb"

# Export to PFX with known password
New-Item -ItemType Directory -Force -Path C:\temp | Out-Null
$pwd = ConvertTo-SecureString "TempLdaps123!" -AsPlainText -Force
Export-PfxCertificate -Cert "Cert:\LocalMachine\My\$thumb" -FilePath C:\temp\ldaps.pfx -Password $pwd

# Remove the CAPI-imported cert
Remove-Item "Cert:\LocalMachine\My\$thumb" -Force

# Re-import using KSP with -sid 22 (Local System) so NTDS can access the key
certutil -f -importpfx -p "TempLdaps123!" -csp "Microsoft Software Key Storage Provider" -sid 22 My "C:\temp\ldaps.pfx"

# Clean up
Remove-Item C:\temp\ldaps.pfx -Force

# Update the NTDS registry key to point to the new thumbprint
$newThumb = (Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*adwest1*" }).Thumbprint
Write-Host "New thumbprint: $newThumb"

$thumbBytes = [byte[]] ($newThumb -split '(?<=\G.{2})' | Where-Object { $_ } | ForEach-Object { [Convert]::ToByte($_, 16) })
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters" -Name "LDAPServerCertificate" -Value $thumbBytes
```

---

## 3. Grant NTDS service access to the private key

NTDS runs as `NETWORK SERVICE` and `NT SERVICE\NTDS`. Both need read access to
the private key file in the KSP machine store.

```powershell
$newThumb = (Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*adwest1*" }).Thumbprint

# Get the key container name from certutil
$certutilOutput = certutil -store My $newThumb | Out-String
$uniqueContainer = ($certutilOutput -split "`n" | Select-String "Unique container").ToString().Split(":")[1].Trim()
$keyPath = "C:\ProgramData\Microsoft\Crypto\Keys\$uniqueContainer"
Write-Host "Key file: $keyPath"

# Grant access
$acl = Get-Acl $keyPath
foreach ($account in @("NETWORK SERVICE", "NT SERVICE\NTDS", "SYSTEM")) {
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($account, "FullControl", "Allow")
    $acl.AddAccessRule($rule)
}
Set-Acl -Path $keyPath -AclObject $acl
Write-Host "Permissions granted"
```

---

## 4. Add Let's Encrypt to the NTAuth store

Windows Server 2025 DCs require the signing CA to be in the NTAuth store before
NTDS will use a cert for LDAPS.

```powershell
# Export the Let's Encrypt intermediate (R12 or R13 depending on issuance date)
$le = Get-ChildItem Cert:\LocalMachine\CA | Where-Object { $_.Subject -match "R1[23]" } | Select-Object -First 1
Export-Certificate -Cert $le -FilePath C:\temp\le-intermediate.cer -Type CERT
certutil -enterprise -addstore NTAuth C:\temp\le-intermediate.cer

# Export ISRG Root X1
$root = Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Subject -like "*ISRG*" } | Select-Object -First 1
Export-Certificate -Cert $root -FilePath C:\temp\isrg-root.cer -Type CERT
certutil -enterprise -addstore NTAuth C:\temp\isrg-root.cer

# Clean up
Remove-Item C:\temp\le-intermediate.cer, C:\temp\isrg-root.cer -Force
```

---

## 5. Restart NTDS and verify

```powershell
Restart-Service NTDS -Force

# Wait for startup then check event log
Start-Sleep -Seconds 15

# Event 1221 = LDAPS bound successfully
# Event 1220 = LDAPS failed
Get-WinEvent -LogName "Directory Service" -MaxEvents 5 |
  Where-Object { $_.Id -in @(1220, 1221, 1222) } |
  Select-Object TimeCreated, Id, Message |
  Format-List

# Also check Schannel — should be no 36886 errors
Get-WinEvent -LogName System -MaxEvents 5 |
  Where-Object { $_.ProviderName -eq "Schannel" -and $_.Id -eq 36886 } |
  Select-Object TimeCreated, Message |
  Format-List
```

Verify from the Terraform runner (Mac):

```sh
openssl s_client -connect adwest1.gvteleport.com:636 -showcerts 2>&1 | head -20
# Should show: depth=0 CN=adwest1.gvteleport.com with Let's Encrypt chain
```

---

## 6. Renewal hook — re-import with KSP after each renewal

win-acme auto-renews via a Scheduled Task but re-imports with CAPI. Create a
post-renewal script so the KSP re-import and NTDS restart happen automatically.

Save as `C:\tools\ldaps-renew-hook.ps1`:

```powershell
# Post-renewal hook for win-acme — re-imports cert with KSP and restarts NTDS
param()

$thumb = (Get-ChildItem Cert:\LocalMachine\My |
  Where-Object { $_.Subject -like "*adwest1*" } |
  Sort-Object NotAfter -Descending |
  Select-Object -First 1).Thumbprint

$pwd = ConvertTo-SecureString "TempLdaps123!" -AsPlainText -Force
Export-PfxCertificate -Cert "Cert:\LocalMachine\My\$thumb" -FilePath C:\temp\ldaps-renew.pfx -Password $pwd
Remove-Item "Cert:\LocalMachine\My\$thumb" -Force
certutil -f -importpfx -p "TempLdaps123!" -csp "Microsoft Software Key Storage Provider" -sid 22 My "C:\temp\ldaps-renew.pfx"
Remove-Item C:\temp\ldaps-renew.pfx -Force

$newThumb = (Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Subject -like "*adwest1*" }).Thumbprint
$thumbBytes = [byte[]] ($newThumb -split '(?<=\G.{2})' | Where-Object { $_ } | ForEach-Object { [Convert]::ToByte($_, 16) })
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters" -Name "LDAPServerCertificate" -Value $thumbBytes

# Grant key permissions
$certutilOutput = certutil -store My $newThumb | Out-String
$uniqueContainer = ($certutilOutput -split "`n" | Select-String "Unique container").ToString().Split(":")[1].Trim()
$keyPath = "C:\ProgramData\Microsoft\Crypto\Keys\$uniqueContainer"
$acl = Get-Acl $keyPath
foreach ($account in @("NETWORK SERVICE", "NT SERVICE\NTDS", "SYSTEM")) {
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($account, "FullControl", "Allow")
    $acl.AddAccessRule($rule)
}
Set-Acl -Path $keyPath -AclObject $acl

Restart-Service NTDS -Force
Write-Host "LDAPS renewal complete. New thumbprint: $newThumb"
```

Configure this as the win-acme post-execution script in `settings.json`:

```json
"Execution": {
  "DefaultPostExecutionScript": "C:\\tools\\ldaps-renew-hook.ps1"
}
```

---

## 7. IAM role permissions required

The EC2 instance's IAM role (`grantvoss-certbot-role-1`) needs these Route53 permissions:

```json
{
  "Effect": "Allow",
  "Action": [
    "route53:GetChange",
    "route53:ListHostedZones",
    "route53:ChangeResourceRecordSets"
  ],
  "Resource": "*"
}
```

---

## 8. Troubleshooting reference

| Symptom | Cause | Fix |
|---|---|---|
| Event 1220, error `8009030e` | NTDS can't read the private key | Grant `NETWORK SERVICE` and `NT SERVICE\NTDS` FullControl on the key file in `C:\ProgramData\Microsoft\Crypto\Keys\` |
| Event 1220, Schannel 36886 `No suitable default server credential` | Cert using legacy CAPI provider | Re-import with `certutil -csp "Microsoft Software Key Storage Provider" -sid 22` |
| LDAPS port 636 TCP reset, no cert presented | LDAPS cert not bound / wrong SANs | Cert CN/SAN must match DC's `dNSHostName` attribute in AD |
| `strongerAuthRequired` on LDAP port 389 | DC requires encrypted bind | Use LDAPS port 636 instead |
| `MI_RESULT_FAILED` from PSWSMan on macOS | WinRM Negotiate failing from non-domain Mac | Use Python ldap3 over LDAPS instead of PSWSMan/WinRM |
| `NTLM needs domain\username` in ldap3 | UPN format passed instead of `DOMAIN\user` | Script auto-converts UPN — ensure `ad_bind_username` is set correctly |
| win-acme `missing --route53accesskeyid` | Session token not supported as CLI flag | Write credentials to `~\.aws\credentials` including `aws_session_token`, or use IAM role |
