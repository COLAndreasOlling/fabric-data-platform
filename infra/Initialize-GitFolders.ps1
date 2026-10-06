<#
.SYNOPSIS
  Makes sure the Git folders the Fabric workspaces sync with exist in the
  repository. Called by Terraform (infra/fabric/git.tf) before connecting the
  workspaces - Fabric's API refuses to connect to a folder that doesn't exist.

.DESCRIPTION
  For every folder that's missing, commits a README.md into it on the given
  branch. Existing folders are left untouched. Never creates the repository or
  the branch: if those are missing it stops with an explanation.

  Input comes from environment variables set by Terraform:
    GIT_PROVIDER      GitHub | AzureDevOps
    GIT_OWNER         GitHub owner
    GIT_ORGANIZATION  Azure DevOps organization
    GIT_PROJECT       Azure DevOps project (plain text, spaces allowed)
    GIT_REPOSITORY    Repository name
    GIT_BRANCH        Branch name
    GIT_DIRECTORIES   Folders separated by ';', e.g. /fabric/DataEngineering;/fabric/ReportingHub

  Credentials come from the session loaded by Load-Credentials.ps1:
    GitHub:       TF_VAR_git_secret (personal access token)
    Azure DevOps: FABRIC_TENANT_ID, FABRIC_CLIENT_ID, FABRIC_CLIENT_SECRET (executor)
#>
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Require([string] $Name) {
  $value = [Environment]::GetEnvironmentVariable($Name)
  if (-not $value) { throw "Environment variable $Name is not set. Load credentials first:  . ./infra/Load-Credentials.ps1 -GitProvider <provider>" }
  return $value
}

function Get-StatusCode($ErrorRecord) {
  if ($ErrorRecord.Exception.Response) { return [int]$ErrorRecord.Exception.Response.StatusCode }
  return 0
}

$provider    = Require 'GIT_PROVIDER'
$repository  = Require 'GIT_REPOSITORY'
$branch      = Require 'GIT_BRANCH'
$directories = (Require 'GIT_DIRECTORIES') -split ';' | Where-Object { $_ } | ForEach-Object { '/' + $_.Trim('/') } | Where-Object { $_ -ne '/' }

if (-not $directories) { Write-Host 'Git: repository root only - nothing to create.'; return }

function New-ReadmeContent([string] $Directory) {
  $name = Split-Path $Directory -Leaf
  return "# $name`n`nFabric items for the $name workspace, synced by Fabric Git integration.`nCreated by Terraform (infra/fabric). Edit items in Fabric, not here.`n"
}

if ($provider -eq 'AzureDevOps') {
  $org     = Require 'GIT_ORGANIZATION'
  $project = Require 'GIT_PROJECT'
  $body = @{
    grant_type    = 'client_credentials'
    client_id     = (Require 'FABRIC_CLIENT_ID')
    client_secret = (Require 'FABRIC_CLIENT_SECRET')
    scope         = '499b84ac-1321-427f-aa17-267ca6975798/.default'   # Azure DevOps
  }
  $token   = (Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$(Require 'FABRIC_TENANT_ID')/oauth2/v2.0/token" -Body $body).access_token
  $headers = @{ Authorization = "Bearer $token" }
  $base    = "https://dev.azure.com/$([Uri]::EscapeDataString($org))/$([Uri]::EscapeDataString($project))/_apis/git/repositories/$([Uri]::EscapeDataString($repository))"

  try {
    $ref = (Invoke-RestMethod -Uri "$base/refs?filter=heads/$branch&api-version=7.1" -Headers $headers).value | Where-Object { $_.name -eq "refs/heads/$branch" }
  } catch {
    $code = Get-StatusCode $_
    throw "Azure DevOps: can't open repository '$repository' in $org/$project (HTTP $code). Check the URL, and that the service principal has Basic access and is a Contributor in the project (guide step 3)."
  }
  if (-not $ref) { throw "Azure DevOps: branch '$branch' doesn't exist in '$repository'. Create it (the repository needs at least one commit) and apply again." }

  $missing = foreach ($dir in $directories) {
    try {
      Invoke-RestMethod -Uri "$base/items?scopePath=$([Uri]::EscapeDataString($dir))&versionDescriptor.version=$([Uri]::EscapeDataString($branch))&api-version=7.1" -Headers $headers | Out-Null
      Write-Host "Git: $dir exists."
    } catch {
      if ((Get-StatusCode $_) -eq 404) { $dir } else { throw }
    }
  }
  if (-not $missing) { return }

  $push = @{
    refUpdates = @(@{ name = "refs/heads/$branch"; oldObjectId = $ref.objectId })
    commits    = @(@{
      comment = "Add Fabric workspace folders: $($missing -join ', ')"
      changes = @($missing | ForEach-Object {
        @{ changeType = 'add'; item = @{ path = "$_/README.md" }; newContent = @{ content = (New-ReadmeContent $_); contentType = 'rawtext' } }
      })
    })
  } | ConvertTo-Json -Depth 10
  try {
    Invoke-RestMethod -Method Post -Uri "$base/pushes?api-version=7.1" -Headers $headers -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($push)) | Out-Null
  } catch {
    $code = Get-StatusCode $_
    throw "Azure DevOps: couldn't commit the folders to '$branch' (HTTP $code). The service principal needs Contribute on the repository, and branch policies must allow direct pushes to '$branch' - or create the folders yourself: $($missing -join ', ')"
  }
  Write-Host "Git: created $($missing -join ', ') on $branch."
}
elseif ($provider -eq 'GitHub') {
  $owner   = Require 'GIT_OWNER'
  $headers = @{
    Authorization          = "Bearer $(Require 'TF_VAR_git_secret')"
    Accept                 = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent'           = 'fabric-data-platform-terraform'
  }
  $base = "https://api.github.com/repos/$owner/$repository"

  try {
    Invoke-RestMethod -Uri "$base/branches/$([Uri]::EscapeDataString($branch))" -Headers $headers | Out-Null
  } catch {
    $code = Get-StatusCode $_
    if ($code -eq 404) { throw "GitHub: repository $owner/$repository or branch '$branch' not found, or the token can't see it. Check the URL, the branch, and that the token has access to this repository." }
    throw "GitHub: can't open $owner/$repository (HTTP $code). Check that the token is valid and not expired."
  }

  foreach ($dir in $directories) {
    $path = $dir.TrimStart('/')
    try {
      Invoke-RestMethod -Uri "$base/contents/$path`?ref=$([Uri]::EscapeDataString($branch))" -Headers $headers | Out-Null
      Write-Host "Git: $dir exists."
      continue
    } catch {
      if ((Get-StatusCode $_) -ne 404) { throw }
    }
    $body = @{
      message = "Add Fabric workspace folder $dir"
      content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((New-ReadmeContent $dir)))
      branch  = $branch
    } | ConvertTo-Json
    try {
      Invoke-RestMethod -Method Put -Uri "$base/contents/$path/README.md" -Headers $headers -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($body)) | Out-Null
    } catch {
      $code = Get-StatusCode $_
      throw "GitHub: couldn't create $dir on '$branch' (HTTP $code). The token needs Contents: Read and write, and branch protection must allow direct commits - or create the folder yourself."
    }
    Write-Host "Git: created $dir on $branch."
  }
}
else {
  throw "GIT_PROVIDER must be GitHub or AzureDevOps, got '$provider'."
}
