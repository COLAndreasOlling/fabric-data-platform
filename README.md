# fabric-data-platform

Source control for my Microsoft Fabric data platform work.

## Layout

| Folder | What goes there |
|---|---|
| `fabric/` | Fabric workspace items (lakehouses, notebooks, pipelines, semantic models, reports). **Managed by Fabric Git integration — don't edit by hand unless you know what you're doing.** |
| `docs/` | Notes, architecture decisions, how-tos. |
| `scripts/` | Helper scripts (e.g. Python, PowerShell) used outside Fabric. |

## Connecting a Fabric workspace to this repo

1. Create a **fine-grained personal access token** on GitHub:
   Settings → Developer settings → Personal access tokens → Fine-grained tokens.
   Give it access to this repository only, with **Contents: Read and write**.
2. In Fabric, open the workspace → **Workspace settings** → **Git integration** → **GitHub**.
3. Add a GitHub account: paste the token and this repo's URL.
4. Choose branch `main` and Git folder `fabric`, then **Connect and sync**.

From then on, use the **Source control** button in the workspace to commit
changes from Fabric to GitHub, or pull updates from GitHub into Fabric.

> If GitHub isn't offered as an option, a Fabric admin must enable the tenant
> setting *"Users can sync workspace items with GitHub repositories"*.

## Day-to-day workflow

1. Create a branch for a change (in Fabric: Source control → Branch out, or locally `git switch -c my-change`).
2. Make changes in Fabric and commit them from the Source control pane.
3. Open a pull request on GitHub, review, and merge to `main`.
4. Run `git pull` locally to get the latest.

## Never commit

Passwords, connection strings, keys, tokens or customer data. Keep secrets in
Azure Key Vault or Fabric connections, and local secrets in `.env` (ignored).
