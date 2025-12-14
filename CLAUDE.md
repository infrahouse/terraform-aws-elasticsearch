# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Terraform module that deploys a multi-node Elasticsearch cluster on AWS. 
It's part of the InfraHouse Terraform module ecosystem (https://github.com/infrahouse).

The module creates:
- Master nodes (default: 3) for cluster management
- Data nodes (default: 3) for storing/indexing data
- Application Load Balancers for both master and data nodes
- CloudWatch logging infrastructure with KMS encryption
- S3 bucket for Elasticsearch snapshots
- TLS certificates and secrets management
- DNS records in Route53

## Development Commands

### Setup
```bash
make bootstrap          # Set up development environment, install dependencies
make install-hooks      # Install pre-commit hooks (runs automatically in bootstrap)
```

### Testing
```bash
make test              # Run full test suite (bootstraps cluster, tests, then destroys)
make test-keep         # Run test and keep resources for debugging
make test-clean        # Run test and destroy resources afterward
pytest -xvvs tests/test_module.py  # Run tests directly with pytest
```

**Important**: Tests use a two-phase bootstrap process:
1. First phase: `bootstrap_mode = true` creates a single master node
2. Second phase: `bootstrap_mode = false` scales to full cluster (masters + data nodes)

The `.bootstrapped` flag file in `test_data/test_module/` tracks bootstrap state.

### Linting and Formatting
```bash
make lint              # Check Terraform formatting (terraform fmt --check)
make format            # Format all Terraform files and Python tests
make fmt               # Alias for format
```

### Documentation
```bash
# terraform-docs automatically updates README.md via pre-commit hook
# The content between <!-- BEGIN_TF_DOCS --> and <!-- END_TF_DOCS --> is auto-generated
```

### Release Process
```bash
make release-patch     # Release x.x.PATCH version
make release-minor     # Release x.MINOR.0 version
make release-major     # Release MAJOR.0.0 version
```

Releases use `git-cliff` to update CHANGELOG.md and `bumpversion` to bump version numbers. Must be on `main` branch.

### Cleanup
```bash
make clean             # Remove test artifacts, .terraform directories, etc.
```

## Architecture

### Two-Tier Node Architecture

The module deploys two types of nodes:

1. **Master Nodes** (`module.elastic_cluster`):
   - Always deployed (even in bootstrap mode)
   - Handle cluster management, metadata, shard allocation
   - Front-ended by ALB at `${cluster_name}.${zone}` and `${cluster_name}-master.${zone}`
   - Configured via `elastic_master_userdata` module
   - Instance profile: `${cluster_name}-master-${random_suffix}`

2. **Data Nodes** (`module.elastic_cluster_data`):
   - Only deployed when `bootstrap_mode = false`
   - Handle indexing and search operations
   - Front-ended by ALB at `${cluster_name}-data.${zone}`
   - Configured via `elastic_data_userdata` module
   - Instance profile: `${cluster_name}-data-${random_suffix}`

Both use the `infrahouse/website-pod/aws` module (pinned to 5.13.0) which provides:
- Auto Scaling Groups with lifecycle hooks
- Application Load Balancers with HTTPS
- Target groups with health checks
- Security groups
- CloudWatch alarms for ALB health monitoring

### Bootstrap Mode

Bootstrap mode is critical for cluster initialization:

- **When `bootstrap_mode = true`**:
  - ASG creates exactly 1 master node
  - No data nodes are created (`count = 0`)
  - Master node has `elasticsearch.bootstrap_cluster = true` in custom facts
  - Lifecycle hook: master nodes complete immediately

- **When `bootstrap_mode = false`**:
  - ASG scales to `cluster_master_count` (default: 3)
  - Data nodes ASG created with `cluster_data_count` (default: 3)
  - Master nodes have `elasticsearch.bootstrap_cluster = false`
  - Both master and data nodes wait for commissioning via lifecycle hook

### Lifecycle Hooks

Two types of hooks orchestrate node joining/leaving:

1. **Launching hooks** (`local.launching_hook_name`):
   - Default result: `ABANDON` (prevents unhealthy nodes)
   - Timeout: 3600 seconds
   - Completed by `ih-elastic cluster commission-node --complete-lifecycle-action`
   - Also uses `update-dns` module hooks for DNS registration

2. **Terminating hooks** (name: "terminating"):
   - Default result: `CONTINUE`
   - Timeout: 3600 seconds
   - Allows graceful node decommissioning

### CloudWatch Logging

Located in `cloudwatch.tf`:

- **Log Group**: `/elasticsearch/${environment}/${cluster_name}` (from `locals.tf`)
- **KMS Encryption**: Customer-managed key with automatic rotation
- **Retention**: Configurable (default: 365 days, minimum: 365 for compliance)
- **IAM Permissions**: Defined in `iam.tf` via `aws_iam_policy_document.cloudwatch_logs_permissions`
- **Custom Facts**: When enabled, adds `cloudwatch_log_group` to userdata

The log group name is passed to instances via cloud-init custom facts, allowing Puppet/configuration management to configure logging agents.

### TLS and Secrets

Located in `tls.tf` and `secrets.tf`:

- **CA Certificate/Key**: Self-signed CA created via `tls_self_signed_cert` and stored in AWS Secrets Manager
- **Elastic Superuser**: Random password stored in `elastic-password` secret
- **Kibana System User**: Random password stored in `kibana_system-password` secret
- All secrets use the `infrahouse/secret/aws` module for storage

### IAM Permissions

In `iam.tf`, the `elastic_permissions` policy document combines:
- S3 permissions for snapshot bucket
- Secrets Manager access for CA certs and passwords
- CloudWatch Logs write permissions (when enabled)
- ASG lifecycle hook completion permissions
- Optional `extra_instance_profile_permissions` from user

### File Organization

- `main.tf`: Core module instantiation (elastic_cluster, elastic_cluster_data, userdata modules)
- `locals.tf`: Local values (service_name, module_version, log_group_name, profile names)
- `cloudwatch.tf`: CloudWatch Logs resources (log group, KMS key, key policy)
- `iam.tf`: IAM policies for instance profiles
- `dns.tf`: Update-dns Lambda modules for master/data nodes
- `s3.tf`: Snapshots S3 bucket
- `secrets.tf`: AWS Secrets Manager resources
- `tls.tf`: TLS certificate generation
- `extra_security_group.tf`: Additional security groups for monitoring (Prometheus exporters)
- `variables.tf`: Input variables
- `outputs.tf`: Output values
- `datasources.tf`: Data sources (AMI, Route53, caller identity, etc.)
- `terraform.tf`: Provider requirements

## Coding Standards

From `.claude/CODING_STANDARD.md`:

### Terraform Conventions
- Use RST docstrings in Python
- Pin Python dependencies to major version with `~=` syntax (e.g., `requests ~= 2.31`)
- Use HEREDOC for long variable/output descriptions
- Only require providers the module directly uses (child modules handle their own)
- Pin included modules to exact versions (e.g., `version = "5.10.0"`)
- Use data source policy documents, not generated JSON

### Tagging
- Use lowercase tags except `Name`
- Always include `created_by_module` tag
- Tag one "main" resource with `module_version` (see `locals.tf`)
- Require `environment` tag from users

### Testing
- Root module must define variables in `terraform.tfvars`
- CI/CD workflows run on self-hosted runners (GitHub runners lack `ih-registry` command)

## Testing Infrastructure

Tests use `pytest-infrahouse` plugin with fixtures:

- **Fixtures** (in `tests/conftest.py`):
  - `bootstrap_cluster`: Context manager that handles two-phase bootstrap
  - Writes `terraform.tfvars` with appropriate `bootstrap_mode` setting
  - Creates `.bootstrapped` flag file to track state

- **Test Structure** (in `tests/test_module.py`):
  - Parameterized by AWS provider version (`~> 5.11`, `~> 6.0`)
  - Cleans `.terraform/` and `.terraform.lock.hcl` before each run
  - Dynamically writes `terraform.tf` with correct provider version
  - Waits for ASG instance refreshes to complete (up to 3600s)
  - Tests CloudWatch logging functionality

- **Test Module** (`test_data/test_module/`):
  - Instantiates the root module with test configuration
  - Uses fixtures for VPC, subnets, Route53 zone
  - Creates EC2 key pair for SSH access

### Running Single Tests
```bash
pytest -xvvs -k aws-6 tests/test_module.py  # Run only AWS 6.x provider test
```

## Pre-commit Hooks

Located in `hooks/pre-commit`:

1. **Terraform formatting**: Runs `terraform fmt --check -recursive` (fails if not formatted)
2. **Documentation**: Runs `terraform-docs .` and auto-stages README.md if changed
   - Documentation is injected between `<!-- BEGIN_TF_DOCS -->` and `<!-- END_TF_DOCS -->` markers
   - Uses `.terraform-docs.yml` configuration

Install hooks with `make install-hooks` (also runs in `make bootstrap`).

## Common Patterns

### Adding New Variables
1. Add to `variables.tf` with description and type
2. Update `.terraform-docs.yml` if variable needs special documentation
3. Pass variable to child modules in `main.tf` if needed
4. Update `test_data/test_module/main.tf` if test needs to exercise it
5. Run `terraform-docs .` to update README.md (or let pre-commit do it)

### Modifying CloudWatch Configuration
CloudWatch resources are conditional on `var.enable_cloudwatch_logging`:
- Resources use `count = var.enable_cloudwatch_logging ? 1 : 0` pattern
- IAM policy statements use conditional merge in `iam.tf`
- Custom facts conditionally include `cloudwatch_log_group` in userdata modules

### Working with Lifecycle Hooks
Both master and data nodes use the same `launching_hook_name`:
- Defined in `locals.tf`: `launching-${random_string.launching_suffix.result}`
- Random suffix ensures uniqueness across clusters
- Nodes complete hook via `ih-elastic cluster commission-node --complete-lifecycle-action`

## Dependencies

This module depends on:
- `infrahouse/website-pod/aws` (5.13.0): Provides ASG, ALB, target groups, and CloudWatch alarms
- `infrahouse/cloud-init/aws` (2.2.2): Generates cloud-init userdata
- `infrahouse/secret/aws` (1.1.1): Manages AWS Secrets Manager secrets
- `infrahouse/update-dns/aws` (1.2.0): Lambda for DNS updates on instance launch/terminate with CloudWatch monitoring

External dependencies for users:
- VPC with subnets (recommended: `infrahouse/service-network/aws`)
- Route53 hosted zone
- EC2 key pair for SSH access
