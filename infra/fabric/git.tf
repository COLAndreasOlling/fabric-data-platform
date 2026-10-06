# Git integration for the Dev workspaces (git_environments). The repository and
# branch must already exist - Terraform only connects to them.
#
# GitHub:       a Fabric connection with a personal access token (git_secret).
# Azure DevOps: a Fabric connection authenticated as the executor service
#               principal (git_secret = its client secret); the service principal
#               must have been added to the Azure DevOps organization.
#
# git_secret is ephemeral and only passed to write-only arguments, so it never
# ends up in the Terraform state.

locals {
  git_is_github = var.git_provider == "GitHub"

  git_github = local.git_is_github ? regex(
    "^https://github\\.com/(?P<owner>[^/]+)/(?P<repo>[^/]+?)(?:\\.git)?/?$", var.git_repository_url
  ) : null

  git_ado = local.git_is_github ? null : regex(
    "^https://(?:[^@/]+@)?dev\\.azure\\.com/(?P<org>[^/]+)/(?P<project>[^/]+)/_git/(?P<repo>[^/?#]+?)/?$", var.git_repository_url
  )

  git_repo = local.git_is_github ? {
    owner      = local.git_github.owner
    org        = null
    project    = null
    repository = local.git_github.repo
    url        = "https://github.com/${local.git_github.owner}/${local.git_github.repo}"
    } : {
    owner      = null
    org        = local.git_ado.org
    project    = replace(local.git_ado.project, "%20", " ")
    repository = local.git_ado.repo
    url        = "https://dev.azure.com/${local.git_ado.org}/${local.git_ado.project}/_git/${local.git_ado.repo}"
  }

  git_root = trim(var.git_folder, "/")

  # Dev workspaces only by default; Prod gets content through deployment.
  git_workspaces = {
    for key, ws in local.workspaces : key => merge(ws, {
      directory = "/${local.git_root == "" ? "" : "${local.git_root}/"}${ws.type}"
    }) if contains(var.git_environments, ws.env)
  }

  git_connection_name = "${var.workspace_name_prefix}git-${coalesce(local.git_repo.owner, local.git_repo.org)}-${local.git_repo.repository}"

  git_connection_id = one(concat(
    fabric_connection.git_github[*].id,
    fabric_connection.git_azure_devops[*].id,
  ))
}

resource "fabric_connection" "git_github" {
  count = local.git_is_github && length(local.git_workspaces) > 0 ? 1 : 0

  display_name      = local.git_connection_name
  connectivity_type = "ShareableCloud"
  privacy_level     = "Organizational"

  connection_details = {
    type            = "GitHubSourceControl"
    creation_method = "GitHubSourceControl.Contents"
    parameters = [
      { name = "url", value = local.git_repo.url },
    ]
  }

  credential_details = {
    credential_type = "Key"
    key_credentials = {
      key_wo         = var.git_secret
      key_wo_version = var.git_secret_version
    }
  }
}

resource "fabric_connection" "git_azure_devops" {
  count = !local.git_is_github && length(local.git_workspaces) > 0 ? 1 : 0

  display_name      = local.git_connection_name
  connectivity_type = "ShareableCloud"
  privacy_level     = "Organizational"

  connection_details = {
    type            = "AzureDevOpsSourceControl"
    creation_method = "AzureDevOpsSourceControl.Contents"
    parameters = [
      { name = "url", value = local.git_repo.url },
    ]
  }

  credential_details = {
    credential_type = "ServicePrincipal"
    service_principal_credentials = {
      tenant_id                = local.platform.tenant_id
      client_id                = local.platform.executor_client_id
      client_secret_wo         = var.git_secret
      client_secret_wo_version = var.git_secret_version
    }
  }
}

# Fabric only connects to folders that already exist, so missing ones are
# created first (a README.md committed into each). Existing folders are left
# alone; the repository and branch are never created. Re-runs when the
# repository, branch or folders change. Credentials come from the session
# (Load-Credentials.ps1), not from Terraform.
resource "terraform_data" "git_folders" {
  count = length(local.git_workspaces) > 0 ? 1 : 0

  triggers_replace = {
    url         = local.git_repo.url
    branch      = var.git_branch
    directories = sort([for ws in local.git_workspaces : ws.directory])
  }

  provisioner "local-exec" {
    interpreter = [var.powershell, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File"]
    command     = abspath("${path.module}/../Initialize-GitFolders.ps1")

    environment = {
      GIT_PROVIDER     = var.git_provider
      GIT_OWNER        = coalesce(local.git_repo.owner, "-")
      GIT_ORGANIZATION = coalesce(local.git_repo.org, "-")
      GIT_PROJECT      = coalesce(local.git_repo.project, "-")
      GIT_REPOSITORY   = local.git_repo.repository
      GIT_BRANCH       = var.git_branch
      GIT_DIRECTORIES  = join(";", sort([for ws in local.git_workspaces : ws.directory]))
    }
  }
}

# Lets the orchestrator use the connection from the workspace's Source control pane.
resource "fabric_connection_role_assignment" "git_orchestrator" {
  count = var.orchestrator_admin && length(local.git_workspaces) > 0 ? 1 : 0

  connection_id = local.git_connection_id
  role          = "User"

  principal = {
    id   = local.orchestrator_object_id
    type = "User"
  }
}

resource "fabric_workspace_git" "this" {
  for_each = local.git_workspaces

  workspace_id            = fabric_workspace.this[each.key].id
  initialization_strategy = var.git_initialization_strategy

  git_provider_details = {
    git_provider_type = var.git_provider
    owner_name        = local.git_repo.owner
    organization_name = local.git_repo.org
    project_name      = local.git_repo.project
    repository_name   = local.git_repo.repository
    branch_name       = var.git_branch
    directory_name    = each.value.directory
  }

  git_credentials = {
    source        = "ConfiguredConnection"
    connection_id = local.git_connection_id
  }

  # Connect after the folders and items exist, so the first sync sees the
  # complete workspace.
  depends_on = [terraform_data.git_folders, fabric_lakehouse.this, fabric_warehouse.this]
}
