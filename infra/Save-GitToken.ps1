<#
.SYNOPSIS
  Stores a GitHub personal access token in the platform Key Vault, for the
  Fabric Git connection. Only needed when the repository is on GitHub.

.DESCRIPTION
  Asks for the token without showing it and saves it as a Key Vault secret
  (default name: git-token). Run it again with a new token when the old one
  expires, then increase git_secret_version in infra/fabric/terraform.tfvars
  and apply.

  The token needs, for the one repository: Contents = Read and write
  (fine-grained token), or the "repo" scope (classic token).

.EXAMPLE
  ./infra/Save-GitToken.ps1

.EXAMPLE
  ./infra/Save-GitToken.ps1 -KeyVaultName my-kv -SecretName my-git-token -ExpiresOn 2027-10-01
#>
[CmdletBinding()]
param(
  [string] $KeyVaultName,
  [string] $SecretName = 'git-token',

  [Parameter(Mandatory = $true, HelpMessage = 'When does the token expire? (yyyy-MM-dd, as set on GitHub)')]
  [datetime] $ExpiresOn,

  # First expiry warning, in days before expiry (same as expiry_warning_days in bootstrap).
  [ValidateRange(31, 365)]
  [int] $WarningDays = 90
)

$ErrorActionPreference = 'Stop'

if (-not $KeyVaultName) {
  $platformFile = Join-Path $PSScriptRoot 'platform.json'
  if (-not (Test-Path $platformFile)) { throw 'infra/platform.json not found - pass -KeyVaultName.' }
  $KeyVaultName = (Get-Content $platformFile -Raw | ConvertFrom-Json).key_vault_name
}

$secure = Read-Host -AsSecureString "GitHub personal access token (input is hidden)"
$plain  = [System.Net.NetworkCredential]::new('', $secure).Password
if (-not $plain) { throw 'No token entered.' }

# Pass the value through a temp file so it doesn't appear in the process list.
$tmp = New-TemporaryFile
try {
  [IO.File]::WriteAllText($tmp.FullName, $plain)
  az keyvault secret set --vault-name $KeyVaultName --name $SecretName --file $tmp.FullName `
    --expires ($ExpiresOn.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')) `
    --content-type 'GitHub personal access token for the Fabric Git connection' -o none --only-show-errors
  if ($LASTEXITCODE -ne 0) { throw "Couldn't save the secret. You need 'Key Vault Secrets Officer' on $KeyVaultName." }
} finally {
  Remove-Item $tmp.FullName -Force
  Remove-Variable plain, secure
}

Write-Host "Saved as secret '$SecretName' in Key Vault '$KeyVaultName' (expires $($ExpiresOn.ToString('yyyy-MM-dd')))." -ForegroundColor Green

# Early warning: Key Vault alerts 30 days before a secret expires, so a reminder
# secret that expires (WarningDays - 30) days earlier gives an alert WarningDays ahead.
$reminderExpires = $ExpiresOn.AddDays(-($WarningDays - 30))
if ($reminderExpires -gt (Get-Date).AddDays(30)) {
  az keyvault secret set --vault-name $KeyVaultName --name "$SecretName-renewal-reminder" `
    --value "$SecretName expires $($ExpiresOn.ToString('yyyy-MM-dd')). Create a new GitHub token, run infra/Save-GitToken.ps1, increase git_secret_version and apply infra/fabric." `
    --expires ($reminderExpires.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')) `
    --content-type 'Reminder (not a credential)' -o none --only-show-errors
  Write-Host "Expiry warnings: $($ExpiresOn.AddDays(-$WarningDays).ToString('yyyy-MM-dd')), $($ExpiresOn.AddDays(-30).ToString('yyyy-MM-dd')) and $($ExpiresOn.ToString('yyyy-MM-dd'))."
} else {
  Write-Host "Token expires in less than $WarningDays days - you'll be warned 30 days before and on the expiry day." -ForegroundColor Yellow
}
