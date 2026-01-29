# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## First Steps

**Your first tool call in this repository MUST be reading .claude/CODING_STANDARD.md.
Do not read any other files, search, or take any actions until you have read it.**
This contains InfraHouse's comprehensive coding standards for Terraform, Python, and general formatting rules.

## Project Overview

Terraform module that deploys a multi-node Elasticsearch cluster on AWS. Part of the InfraHouse Terraform module ecosystem (https://github.com/infrahouse).

The module creates:
- Master nodes (default: 3) for cluster management
- Data nodes (default: 3) for storing/indexing data
- Application Load Balancers for both master and data nodes
- CloudWatch logging infrastructure with KMS encryption
- S3 bucket for Elasticsearch snapshots
- TLS certificates and secrets management
- DNS records in Route53

## Development Commands

```bash
make bootstrap          # Set up dev environment, install dependencies and hooks
make test               # Run full test suite (bootstraps cluster, tests, then destroys)
make test-keep          # Run test and keep resources for debugging
make test-clean         # Run test and destroy resources afterward
make lint               # Check Terraform formatting
make format             # Format Terraform files and Python tests
make clean              # Remove test artifacts, .terraform directories
```

### Running Single Tests
```bash
pytest -xvvs -k aws-6 tests/test_module.py   # Run only AWS 6.x provider test
pytest -xvvs -k aws-5 tests/test_module.py   # Run only AWS 5.x provider test
```

### Release Process
```bash
make release-patch      # Release x.x.PATCH version
make release-minor      # Release x.MINOR.0 version
make release-major      # Release MAJOR.0.0 version
```
Must be on `main` branch. Uses `git-cliff` for changelog and `bumpversion` for version bumping.

## Architecture

### Two-Tier Node Architecture

1. **Master Nodes** (`module.elastic_cluster` in `main.tf`):
   - Always deployed (even in bootstrap mode)
   - Handle cluster management, metadata, shard allocation
   - ALB endpoints: `${cluster_name}.${zone}` and `${cluster_name}-master.${zone}`
   - Userdata: `elastic_master_userdata` module
   - Instance profile: `${cluster_name}-master-${random_suffix}`

2. **Data Nodes** (`module.elastic_cluster_data` in `main.tf`):
   - Only deployed when `bootstrap_mode = false`
   - Handle indexing and search operations
   - ALB endpoint: `${cluster_name}-data.${zone}`
   - Userdata: `elastic_data_userdata` module
   - Instance profile: `${cluster_name}-data-${random_suffix}`

Both use `infrahouse/website-pod/aws` module (pinned to 5.13.0) providing ASGs, ALBs, target groups, and CloudWatch alarms.

### Bootstrap Mode

Critical for cluster initialization:

- **`bootstrap_mode = true`**: Creates 1 master node, no data nodes. Master has `elasticsearch.bootstrap_cluster = true`.
- **`bootstrap_mode = false`**: Scales to full cluster (3 masters + 3 data nodes by default). All nodes join via lifecycle hooks.

Tests use a two-phase bootstrap tracked by `.bootstrapped` flag file in `test_data/test_module/`.

### Lifecycle Hooks

- **Launching hooks** (`local.launching_hook_name` in `locals.tf`): Default `ABANDON`, 3600s timeout. Nodes complete via `ih-elastic cluster commission-node --complete-lifecycle-action`.
- **Terminating hooks**: Default `CONTINUE`, 3600s timeout for graceful decommissioning.

### File Organization

| File | Purpose |
|------|---------|
| `main.tf` | Core module instantiation (elastic_cluster, elastic_cluster_data, userdata) |
| `locals.tf` | Local values (service_name, module_version, log_group_name, profile names) |
| `cloudwatch.tf` | CloudWatch Logs resources (log group, KMS key) |
| `iam.tf` | IAM policies for instance profiles |
| `dns.tf` | Update-dns Lambda modules for master/data nodes |
| `s3.tf` | Snapshots S3 bucket |
| `secrets.tf` | AWS Secrets Manager resources |
| `tls.tf` | TLS certificate generation |
| `extra_security_group.tf` | Security groups for monitoring (Prometheus exporters) |

### Key Dependencies

- `infrahouse/website-pod/aws` (5.13.0): ASG, ALB, target groups, CloudWatch alarms
- `infrahouse/cloud-init/aws` (2.2.2): Cloud-init userdata generation
- `infrahouse/secret/aws` (1.1.1): AWS Secrets Manager secrets
- `infrahouse/update-dns/aws` (1.2.0): Lambda for DNS updates on instance launch/terminate

## Testing

Tests use `pytest-infrahouse` plugin with fixtures in `tests/conftest.py`:

- **`bootstrap_cluster`**: Context manager handling two-phase bootstrap
- Tests parameterized by AWS provider version (`~> 5.11`, `~> 6.0`)
- Cleans `.terraform/` and `.terraform.lock.hcl` before each run
- Waits for ASG instance refreshes (up to 3600s)

Test module at `test_data/test_module/` instantiates the root module with test configuration.

## Coding Standards

Follow `.claude/CODING_STANDARD.md` for InfraHouse conventions:

### Terraform
- Use HEREDOC for long variable/output descriptions
- Pin modules to exact versions (e.g., `version = "5.13.0"`)
- Use data source policy documents, not generated JSON
- Only require providers the module directly uses

### Tagging
- Use lowercase tags except `Name`
- Always include `created_by_module` tag
- Tag one "main" resource with `module_version` (see `locals.tf`)
- Require `environment` tag from users

### Pre-commit Hooks
Located in `hooks/pre-commit`:
1. Terraform formatting check (`terraform fmt --check -recursive`)
2. Auto-update README.md with `terraform-docs` (content between `<!-- BEGIN_TF_DOCS -->` markers)

## Common Patterns

### Adding New Variables
1. Add to `variables.tf` with description and type
2. Pass to child modules in `main.tf` if needed
3. Update `test_data/test_module/main.tf` if test exercises it
4. Run `terraform-docs .` to update README.md

### Modifying CloudWatch Configuration
Resources conditional on `var.enable_cloudwatch_logging`:
- Use `count = var.enable_cloudwatch_logging ? 1 : 0` pattern
- IAM policy statements use conditional merge in `iam.tf`
- Custom facts conditionally include `cloudwatch_log_group` in userdata modules
