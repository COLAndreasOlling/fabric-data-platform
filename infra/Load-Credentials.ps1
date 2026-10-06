<#
.SYNOPSIS
  Loads the executor service principal's credentials (and the Git secret) from
  Key Vault into the current PowerShell session, for infra/capacities and
  infra/fabric.

.DESCRIPTION
  Run it with a leading dot so the variables stay in your session:

      . ./infra/Load-Credentials.ps1

  It asks for anything it needs that isn't given as a parameter, checks that
  you're signed in to the right tenant, and never prints a secret.

  Values come from infra/platform.json (tenant, client ID, Key Vault) unless you
  pass them. Secrets are read from Key Vault with your own `az login`.

.PARAMETER GitProvider
  GitHub or AzureDevOps - the same value as git_provider in Terraform.

.PARAMETER KeyVaultName
  Vault holding the secrets. Default: key_vault_name in platform.json.

.PARAMETER ClientSecretName
  Secret with the executor's client secret. Default: executor-client-secret.

.PARAMETER GitTokenSecretName
  GitHub only: secret with the personal access token. Default: git-token.
  Store it with ./infra/Save-GitToken.ps1.

.EXAMPLE
  . ./infra/Load-Credentials.ps1 -GitProvider GitHub

.EXAMPLE
  # Existing environment with its own vault and secret name
  . ./infra/Load-Credentials.ps1 -GitProvider AzureDevOps -KeyVaultName my-kv -ClientSecretName my-sp-secret
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, HelpMessage = 'Where is the repository? GitHub or AzureDevOps')]
  [ValidateSet('GitHub', 'AzureDevOps')]
  [string] $GitProvider,

  [string] $KeyVaultName,
  [string] $ClientSecretName = 'executor-client-secret',
  [string] $GitTokenSecretName = 'git-token'
)

if ($MyInvocation.InvocationName -ne '.') {
  Write-Error 'Run this script with a leading dot so the variables stay in your session:  . ./infra/Load-Credentials.ps1'
  return
}

$ErrorActionPreference = 'Stop'

$platformFile = Join-Path $PSScriptRoot 'platform.json'
if (-not (Test-Path $platformFile)) {
  throw "infra/platform.json not found. Run bootstrap first, or create it from infra/platform.example.json (existing environment)."
}
$platform = Get-Content $platformFile -Raw | ConvertFrom-Json
if (-not $KeyVaultName) { $KeyVaultName = $platform.key_vault_name }

# Signed in to the right tenant as a person?
$account = az account show --query "{tenant:tenantId, user:user.name, type:user.type}" -o json --only-show-errors 2>$null | ConvertFrom-Json
if (-not $account) {
  throw "Not signed in to Azure CLI. Run:  az login --tenant $($platform.tenant_id)   (or add --use-device-code to pick the account in a browser)"
}
if ($account.tenant -ne $platform.tenant_id) {
  throw "Azure CLI is signed in to tenant $($account.tenant), but platform.json is for $($platform.tenant_id). Run:  az login --tenant $($platform.tenant_id)"
}
if ($account.type -ne 'user') {
  throw "Azure CLI is signed in as a service principal. Sign in as yourself (the orchestrator) with az login."
}

function Get-VaultSecret([string] $Name) {
  $value = az keyvault secret show --vault-name $KeyVaultName --name $Name --query value -o tsv --only-show-errors 2>$null
  if (-not $value) {
    throw "Couldn't read secret '$Name' from Key Vault '$KeyVaultName'. Check the name, and that you have 'Key Vault Secrets User' (or Officer) on the vault."
  }
  return $value
}

$clientSecret = Get-VaultSecret $ClientSecretName

$env:ARM_TENANT_ID        = $platform.tenant_id
$env:ARM_CLIENT_ID        = $platform.executor_client_id
$env:ARM_CLIENT_SECRET    = $clientSecret
$env:FABRIC_TENANT_ID     = $platform.tenant_id
$env:FABRIC_CLIENT_ID     = $platform.executor_client_id
$env:FABRIC_CLIENT_SECRET = $clientSecret

if ($GitProvider -eq 'GitHub') {
  $env:TF_VAR_git_secret = Get-VaultSecret $GitTokenSecretName
} else {
  # Azure DevOps connects as the executor service principal itself.
  $env:TF_VAR_git_secret = $clientSecret
}
Remove-Variable clientSecret

Write-Host ''
Write-Host "Credentials loaded for this PowerShell session:" -ForegroundColor Green
Write-Host "  Orchestrator (you)  : $($account.user)"
Write-Host "  Tenant              : $($platform.tenant_id)"
Write-Host "  Service principal   : $($platform.executor_client_id)"
Write-Host "  Key Vault           : $KeyVaultName"
Write-Host "  Git provider        : $GitProvider ($(if ($GitProvider -eq 'GitHub') { "token from secret '$GitTokenSecretName'" } else { 'executor service principal' }))"
Write-Host ''
Write-Host "Open a new terminal? Run this again." -ForegroundColor DarkGray
