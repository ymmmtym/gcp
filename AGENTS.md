# AGENTS.md

## Overview

Terraform repo managing GCP infrastructure (GCE, firewall, GCS) via Terraform Cloud.
Flat structure — no modules, no local workspaces, no subdirectories.
Uses a Terraform Cloud remote workspace (`gcp`).

## Key Versions

- Terraform: `~> 1.15.0`
- Provider: `hashicorp/google ~> 7.0` (locked at 7.40.0)
- gcloud CLI: managed via `mise.toml`

## Workflow

1. Create a branch from `main`
2. Edit/add `.tf` files
3. Open a PR → Terraform Cloud runs `terraform plan` (dry-run)
4. Merge → Terraform Cloud runs `terraform apply` (deploy)

Local validation via prek hooks (`prek run --all-files`):
- `terraform_fmt` — auto-format `.tf` files
- `terraform_validate` — syntax/config validation
- `terraform_tflint` — linting
- `terraform_tfsec` — security scanning
- `terraform_providers_lock` — lockfile consistency

Terraform Cloud also runs `plan`/`apply` on PR merge.

## Local Development

```bash
# Requires credentials.json from GCP (terraform.tfvars is auto-loaded if present, but gitignored)
terraform init
terraform plan -var "GCP_CREDENTIALS=$(cat credentials.json)"
terraform apply -var "GCP_CREDENTIALS=$(cat credentials.json)"
```

gcloud CLI is available via mise:
```bash
mise install
```

## Conventions

- Commit messages: Conventional Commits (e.g., `chore: ...`, `feat: ...`, `fix: ...`)
- Renovate manages dependency updates (`renovate.json` extends `github>ymmmtym/.github`)
- `.gitignore` excludes `/*.tfvars`, `/*.tfstate`, `*.json` (root-only), `.terraform/` — never commit these
- Variables (`GCP_CREDENTIALS`, `PROJECT_ID`, `REGION`) are set in Terraform Cloud workspace, not in files
