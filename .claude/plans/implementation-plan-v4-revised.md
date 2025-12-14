# Revised Implementation Plan: terraform-aws-elasticsearch v4.0.0

**Date:** 2025-12-13
**Current Version:** 3.12.0
**Target Version:** 4.0.0
**Type:** BREAKING CHANGE - Major Version Bump

---

## Implementation Checklist (Working List)

### Phase 1: Code Changes ✅

#### Module Updates
- [x] Update `main.tf`: website-pod to 5.13.0 (lines 112, 187) - fixes SNS topic naming conflict
- [x] Update `dns.tf`: update-dns to 1.2.0 (lines 2, 11)
- [x] Update `secrets.tf`: secret to 1.1.1 (lines 7, 32)
- [x] Keep `tls.tf` as is (already uses ~> 1.0)

#### Variable Additions
- [x] Add all alarm variables to `variables.tf` after line 225
- [x] Add validations to existing variables (cluster counts, CIDR blocks, cluster name)
- [x] Add type declarations to puppet variables

#### Module Parameters
- [x] Add alarm parameters to `module.elastic_cluster` in `main.tf`
- [x] Add alarm parameters to `module.elastic_cluster_data` in `main.tf`
- [x] Add alarm parameters to both DNS modules in `dns.tf`

#### Outputs
- [x] Add alarm SNS topic ARN outputs
- [x] Add additional outputs (backend_security_group_id, vpc_id, etc.)

#### Bug Fixes
- [x] Timeout units NOT a bug (correctly uses seconds, not minutes)
- [x] TLS validity NOT fixed (356 → 365 would recreate CA certificate and break SSL chain)
- [x] Fix description in `extra_security_group.tf` line 48 ONLY
- [x] Template comment already removed from `secrets.tf` during module update
- [x] Security group Names NOT fixed (would cause recreation)

#### Test Updates
- [x] Update test module with alarm_emails
- [x] Change monitoring_cidr_block to VPC CIDR

### Phase 2: Testing 🧪

#### Development Testing
- [x] Run `make test-keep`
- [x] Verify CloudWatch alarms created
- [x] Check SNS topics and subscriptions
- [x] Manual verification in AWS Console

#### Pre-PR Testing
- [ ] Run `make test-clean`

### Phase 3: Documentation 📝
- [x] Add Alert Configuration section to README.md
- [x] Run terraform-docs to update inputs/outputs
- [x] Update CLAUDE.md dependencies

### Phase 4: Release 🚀

- [ ] Create feature branch
- [ ] Commit all changes
- [ ] Create pull request
- [ ] Wait for CI to pass
- [ ] Merge to main
- [ ] Update CHANGELOG.md with v4.0.0 entry
- [ ] Run `make release-major`
- [ ] Push tags: `git push && git push --tags`

---

## Executive Summary

This revised plan incorporates the latest dependency versions and careful consideration of resource recreation impacts:

1. **Module Dependency Updates:**
   - `website-pod`: 5.10.0 → 5.12.1 (adds CloudWatch alarms for Vanta compliance)
   - `update-dns`: 0.11.1 → **1.2.0** (latest version with enhanced monitoring)
   - `secret`: 1.1.0 → **1.1.1** (bug fix for role assumption)

2. **Alert Capabilities:** Comprehensive CloudWatch alarms for ALB and Lambda monitoring

3. **Critical Bug Fixes:** Timeout units bug, TLS validity calculation, type declarations

4. **IMPORTANT:** Security group name typos will NOT be fixed to avoid resource recreation

---

## 1. Module Dependency Updates

### 1.1 website-pod: 5.10.0 → 5.12.1

**Changes from CHANGELOG:**
- v5.12.0: Added optional CloudWatch alarms for Vanta compliance
- v5.12.1: Fixed Terraform 1.12.2 compatibility (ternary operator in validation blocks)
- No breaking changes

**Files to Update:**
- `main.tf` (lines 112, 176)

```hcl
# Update both elastic_cluster and elastic_cluster_data modules:
module "elastic_cluster" {
  source  = "registry.infrahouse.com/infrahouse/website-pod/aws"
  version = "5.12.1"  # was 5.10.0
  # ...
}
```

### 1.2 update-dns: 0.11.1 → 1.2.0 (NOT 1.0.0)

**Changes from CHANGELOG:**
- v1.0.0: Major version with CloudWatch alarms via terraform-aws-lambda-monitored
- v1.1.0: Support for multiple DNS records per instance
- v1.2.0: Fix DNS cleanup on termination, add validation
- **100% backward compatible** - no breaking changes

**Files to Update:**
- `dns.tf` (lines 2, 11)

```hcl
module "update-dns" {
  source  = "registry.infrahouse.com/infrahouse/update-dns/aws"
  version = "1.2.0"  # was 0.11.1
  # ...
}
```

### 1.3 secret: 1.1.0 → 1.1.1

**Changes from CHANGELOG:**
- v1.1.1: Bug fix - Skip role assumption when already using target role (#34, #35)
- No breaking changes

**Files to Update:**
- `secrets.tf` (lines 7, 32)
- `tls.tf` (lines 27, 45)

```hcl
module "elastic-password" {
  source  = "registry.infrahouse.com/infrahouse/secret/aws"
  version = "1.1.1"  # was 1.1.0
  # ...
}
```

**Note:** `tls.tf` uses `version = "~> 1.0"` which already includes 1.1.1, so no change needed there.

---

## 2. Alert Capabilities Implementation

### 2.1 Variable Additions

**File:** `variables.tf` (insert after line 225 - after `sns_topic_alarm_arn`)

```hcl
variable "alarm_emails" {
  description = <<-EOT
    List of email addresses to receive CloudWatch alarm notifications for Elasticsearch cluster monitoring.
    Covers ALB health, Lambda function errors, and infrastructure issues.

    IMPORTANT: After deployment, AWS SNS will send confirmation emails to each address.
    You MUST click the confirmation link in each email to activate notifications.

    At least one email address is required for all environments (dev needs monitoring too!).
  EOT
  type        = list(string)
  default     = []  # Empty default for backward compatibility

  validation {
    condition     = length(var.alarm_emails) > 0
    error_message = "At least one alarm email address is required. Development environments need monitoring too!"
  }
}

variable "alarm_topic_arns" {
  description = <<-EOT
    List of existing SNS topic ARNs to receive CloudWatch alarm notifications.
    Use this for advanced integrations with PagerDuty, Slack, OpsGenie, etc.
    These topics receive notifications alongside alarm_emails.
  EOT
  type        = list(string)
  default     = []
}

# ALB Alarm Thresholds (with sensible defaults for Elasticsearch)
variable "alarm_unhealthy_host_threshold" {
  description = "Number of unhealthy hosts before triggering alarm. Set to 0 for immediate alerting, 1 to alert when 2+ hosts are unhealthy."
  type        = number
  default     = 1  # Alert when 2 or more nodes are unhealthy (allows for rolling updates)
}

variable "alarm_target_response_time_threshold" {
  description = "Target response time threshold in seconds. Defaults to 80% of idle_timeout if not specified."
  type        = number
  default     = null  # Will default to 80% of idle_timeout in module logic
}

variable "alarm_success_rate_threshold" {
  description = "Minimum success rate percentage (non-5xx responses). Defaults to 99.0%."
  type        = number
  default     = 99.0
}

variable "alarm_cpu_utilization_threshold" {
  description = "CPU utilization percentage threshold for alarms. Defaults to autoscaling target + 30%."
  type        = number
  default     = null  # Will be calculated based on autoscaling_target_cpu_load
}

variable "alarm_evaluation_periods" {
  description = "Number of consecutive periods exceeding threshold before triggering alarm."
  type        = number
  default     = 2  # Conservative default to avoid false positives

  validation {
    condition     = var.alarm_evaluation_periods >= 1
    error_message = "Alarm evaluation periods must be at least 1."
  }
}

variable "alarm_success_rate_period" {
  description = "Time window in seconds for success rate calculation. Must be 60, 300, 900, or 3600."
  type        = number
  default     = 300

  validation {
    condition     = contains([60, 300, 900, 3600], var.alarm_success_rate_period)
    error_message = "Success rate period must be 60, 300, 900, or 3600 seconds."
  }
}

# No alert_strategy variable - DNS failures are critical and always use immediate alerting
```

### 2.2 Module Parameter Updates

**File:** `main.tf`

Add these parameters to `module.elastic_cluster` (after line ~158):

```hcl
  # Alert Configuration (new in v4.0.0)
  alarm_emails                          = var.alarm_emails
  alarm_topic_arns                      = var.alarm_topic_arns
  alarm_unhealthy_host_threshold        = var.alarm_unhealthy_host_threshold
  alarm_target_response_time_threshold  = var.alarm_target_response_time_threshold
  alarm_success_rate_threshold          = var.alarm_success_rate_threshold
  alarm_success_rate_period            = var.alarm_success_rate_period
  alarm_cpu_utilization_threshold       = var.alarm_cpu_utilization_threshold
  alarm_evaluation_periods              = var.alarm_evaluation_periods
```

Add the same to `module.elastic_cluster_data` (after line ~227):

```hcl
  # Alert Configuration (new in v4.0.0)
  alarm_emails                          = var.alarm_emails
  alarm_topic_arns                      = var.alarm_topic_arns
  alarm_unhealthy_host_threshold        = var.alarm_unhealthy_host_threshold
  alarm_target_response_time_threshold  = var.alarm_target_response_time_threshold
  alarm_success_rate_threshold          = var.alarm_success_rate_threshold
  alarm_success_rate_period            = var.alarm_success_rate_period
  alarm_cpu_utilization_threshold       = var.alarm_cpu_utilization_threshold
  alarm_evaluation_periods              = var.alarm_evaluation_periods
```

**File:** `dns.tf`

Add to `module.update-dns` (after line ~7):

```hcl
  # Alert Configuration (new in v4.0.0)
  alarm_emails    = var.alarm_emails
  alert_strategy  = "immediate"  # DNS failures are critical - always alert immediately
```

Add to `module.update-dns-data` (after line ~16):

```hcl
  # Alert Configuration (new in v4.0.0)
  alarm_emails    = var.alarm_emails
  alert_strategy  = "immediate"  # DNS failures are critical - always alert immediately
```

### 2.3 Output Additions

**File:** `outputs.tf` (add at end)

```hcl
# Alert Outputs (new in v4.0.0)
output "alarm_sns_topic_arn" {
  description = "ARN of the SNS topic used for alarm notifications (from master nodes ALB)"
  value       = module.elastic_cluster.sns_topic_arn
}

output "alarm_sns_topic_arn_data" {
  description = "ARN of the SNS topic used for alarm notifications (from data nodes ALB)"
  value       = var.bootstrap_mode ? null : module.elastic_cluster_data[0].sns_topic_arn
}

output "dns_lambda_sns_topic_arn" {
  description = "ARN of the SNS topic for DNS Lambda monitoring"
  value       = module.update-dns.sns_topic_arn
}

output "dns_lambda_sns_topic_arn_data" {
  description = "ARN of the SNS topic for DNS Lambda monitoring (data nodes)"
  value       = module.update-dns-data.sns_topic_arn
}

# Additional useful outputs
output "backend_security_group_id" {
  description = "ID of the security group used for Elasticsearch transport protocol"
  value       = aws_security_group.backend_extra.id
}

output "vpc_id" {
  description = "VPC ID where the Elasticsearch cluster is deployed"
  value       = data.aws_subnet.selected.vpc_id
}

output "cloudwatch_kms_key_alias" {
  description = "Alias of the KMS key used for CloudWatch log encryption"
  value       = var.enable_cloudwatch_logging ? aws_kms_alias.cloudwatch_logs[0].name : null
}
```

---

## 3. Critical Bug Fixes (NO Security Group Name Changes)

### 3.1 IMPORTANT: Typos That Will NOT Be Fixed

**REASON:** Changing security group Names would cause resource recreation, which is disruptive.

**File:** `extra_security_group.tf`

The following typos will **remain unchanged** to avoid recreation:
- Line 8: `Name = "Elasticseach ${var.cluster_name} transport"` - KEEP AS IS
- Line 56: `Name = "Prometheus elsaticsearch exporter"` - KEEP AS IS

Only fix the **description** which doesn't cause recreation:
- Line 48: Change description from `"Prometheus node exporter"` to `"Prometheus elasticsearch exporter"`

```hcl
# Line 48 only - fix description:
resource "aws_vpc_security_group_ingress_rule" "elastic_exporter" {
  count             = var.monitoring_cidr_block == null ? 0 : 1
  description       = "Prometheus elasticsearch exporter"  # Fixed typo in description only
  # ... rest unchanged ...
}
```

### 3.2 Critical Timeout Units Bug

**File:** `main.tf` (line 216)

```hcl
# Current (BUG):
wait_for_capacity_timeout = "${var.asg_health_check_grace_period * 1.5}s"

# Fixed:
wait_for_capacity_timeout = "${var.asg_health_check_grace_period * 1.5}m"
```

**Impact:** This is critical - data nodes currently wait only 1350 seconds (22.5 min) instead of intended ~22.5 hours.

### 3.3 TLS Certificate Validity

**File:** `tls.tf` (line 17)

```hcl
# Current (typo):
validity_period_hours = 24 * 356 * 100  # 99.726 years

# Fixed:
validity_period_hours = 24 * 365 * 100  # 100 years
```

### 3.4 Add Missing Type Declarations

**File:** `variables.tf`

Line 141-144:
```hcl
variable "puppet_hiera_config_path" {
  description = "Path to hiera configuration file."
  type        = string  # ADD THIS LINE
  default     = "{root_directory}/environments/{environment}/hiera.yaml"
}
```

Line 152-155:
```hcl
variable "puppet_module_path" {
  description = "Path to common puppet modules."
  type        = string  # ADD THIS LINE
  default     = "{root_directory}/environments/{environment}/modules:{root_directory}/modules"
}
```

### 3.5 Remove Leftover Template Comment

**File:** `secrets.tf` (line 33)

Remove the line: `# insert the 2 required variables here`

---

## 4. Variable Validations

### 4.1 Cluster Master Count Validation

**File:** `variables.tf` (lines 31-35)

```hcl
variable "cluster_master_count" {
  description = "Number of master nodes in the cluster (must be odd for quorum)"
  type        = number
  default     = 3

  validation {
    condition     = var.cluster_master_count % 2 == 1
    error_message = "cluster_master_count must be an odd number for Elasticsearch quorum (e.g., 1, 3, 5, 7)."
  }

  validation {
    condition     = var.cluster_master_count >= 1
    error_message = "cluster_master_count must be at least 1."
  }
}
```

### 4.2 Cluster Data Count Validation

**File:** `variables.tf` (lines 37-41)

```hcl
variable "cluster_data_count" {
  description = "Number of data nodes in the cluster"
  type        = number
  default     = 3

  validation {
    condition     = var.cluster_data_count >= 1
    error_message = "cluster_data_count must be at least 1."
  }
}
```

### 4.3 SSH CIDR Block Security

**File:** `variables.tf` (lines 193-197)

```hcl
variable "ssh_cidr_block" {
  description = <<-EOT
    CIDR range that is allowed to SSH into the elastic instances.
    Defaults to VPC CIDR block for security.
    Set to a more restrictive range for production environments.
  EOT
  type        = string
  default     = null  # Will use VPC CIDR if not specified
}
```

**Note:** The module will need to add logic to use VPC CIDR when null:

**File:** `main.tf` (add after datasources, around line 10)

```hcl
# Get VPC CIDR for secure SSH default
data "aws_vpc" "selected" {
  id = data.aws_subnet.selected.vpc_id
}

locals {
  # Use VPC CIDR as default for SSH access (much more secure than 0.0.0.0/0)
  ssh_cidr_block = coalesce(var.ssh_cidr_block, data.aws_vpc.selected.cidr_block)
}
```

Then update both module calls to use `local.ssh_cidr_block` instead of `var.ssh_cidr_block`.

### 4.4 Monitoring CIDR Validation

**File:** `variables.tf` (lines 199-203)

```hcl
variable "monitoring_cidr_block" {
  description = "CIDR range that is allowed to monitor elastic instances."
  type        = string
  default     = null

  validation {
    condition = (
      var.monitoring_cidr_block == null ||
      !can(regex("^0\\.0\\.0\\.0/0$", var.monitoring_cidr_block))
    )
    error_message = "Monitoring CIDR block should not be 0.0.0.0/0. Specify a restricted CIDR range for security."
  }
}
```

### 4.5 Cluster Name Length Validation

**File:** `variables.tf` (lines 25-29)

```hcl
variable "cluster_name" {
  description = "How to name the cluster"
  type        = string
  default     = "elastic"

  validation {
    condition     = length(var.cluster_name) >= 1 && length(var.cluster_name) <= 32
    error_message = "cluster_name must be between 1 and 32 characters for ALB name_prefix compatibility."
  }
}
```

---

## 5. Testing Updates

### 5.1 Test Module Configuration

**File:** `test_data/test_module/main.tf`

Add after line ~23:

```hcl
  # Alert configuration (new in v4.0.0)
  alarm_emails = [
    "test-elasticsearch-alerts@infrahouse.com"
  ]

  # DNS Lambda alerts are always "immediate" - critical for node provisioning
```

Change line 19:
```hcl
  # Changed from 0.0.0.0/0 to VPC CIDR for security
  monitoring_cidr_block = "10.1.0.0/16"
```

### 5.2 No Additional Test Functions Needed

**Note:** Alert functionality is provided by the dependency modules (website-pod and update-dns). 
These modules are already tested in their own repositories, so we don't need to duplicate alert testing here. 
The existing tests will continue to work with the new alarm outputs available.

---

## 6. Documentation Updates

### 6.1 CHANGELOG.md Entry

```markdown
## [4.0.0] - 2025-XX-XX

### BREAKING CHANGES

- **Module Dependencies Updated:**
  - `infrahouse/website-pod/aws`: 5.10.0 → 5.12.1 (adds CloudWatch alarms)
  - `infrahouse/update-dns/aws`: 0.11.1 → 1.2.0 (adds CloudWatch alarms, DNS cleanup fixes)
  - `infrahouse/secret/aws`: 1.1.0 → 1.1.1 (role assumption bug fix)

- **New Required Variable:**
  - `alarm_emails`: Required for ALL environments (including development) for CloudWatch alarm notifications
  - SNS confirmation emails will be sent to each address and must be confirmed
  - Every environment deserves proper monitoring!

- **Enhanced Security Defaults and Validations:**
  - `ssh_cidr_block`: Now defaults to VPC CIDR instead of 0.0.0.0/0 (much more secure!)
  - `monitoring_cidr_block`: Cannot be 0.0.0.0/0
  - `cluster_master_count`: Must be odd number for Elasticsearch quorum
  - `cluster_name`: Length must be between 1-32 characters

### Added

- **Comprehensive CloudWatch Alarm Monitoring:**
  - ALB health alarms (unhealthy hosts, latency, 5xx errors, CPU utilization)
  - DNS Lambda alarms (errors, throttling, duration)
  - Configurable alarm thresholds and evaluation periods
  - Support for external SNS topic integrations (PagerDuty, Slack, OpsGenie)

- **New Variables:**
  - `alarm_emails` - Email addresses for alarm notifications (required)
  - `alarm_topic_arns` - Additional SNS topics for integrations
  - `alarm_unhealthy_host_threshold` - Unhealthy host count threshold
  - `alarm_target_response_time_threshold` - Response time threshold
  - `alarm_success_rate_threshold` - Success rate percentage threshold
  - `alarm_success_rate_period` - Time window for success rate calculation
  - `alarm_cpu_utilization_threshold` - CPU utilization threshold
  - `alarm_evaluation_periods` - Consecutive periods before alerting
  - NOTE: DNS Lambda alerts always use "immediate" strategy (hardcoded for critical operations)

- **New Outputs:**
  - `alarm_sns_topic_arn` - Master nodes alarm SNS topic ARN
  - `alarm_sns_topic_arn_data` - Data nodes alarm SNS topic ARN
  - `dns_lambda_sns_topic_arn` - DNS Lambda alarm SNS topic ARN
  - `dns_lambda_sns_topic_arn_data` - Data nodes DNS Lambda alarm SNS topic ARN
  - `backend_security_group_id` - Backend security group ID
  - `vpc_id` - VPC ID where cluster is deployed
  - `cloudwatch_kms_key_alias` - CloudWatch KMS key alias

### Fixed

- **Critical Bug:** Data node `wait_for_capacity_timeout` now correctly uses minutes instead of seconds
- **TLS Certificate:** Fixed validity calculation from 356 to 365 days
- **Variable Types:** Added missing type declarations for `puppet_hiera_config_path` and `puppet_module_path`
- **Code Cleanup:** Removed leftover template comments
- **Security Group:** Fixed description for Prometheus elasticsearch exporter (line 48 only)

### Changed

- Test module now uses VPC CIDR (10.1.0.0/16) for `monitoring_cidr_block` instead of 0.0.0.0/0

### Migration Guide

1. **Add alarm_emails for production:**
   ```hcl
   module "elasticsearch" {
     source  = "infrahouse/elasticsearch/aws"
     version = "4.0.0"

     # Required for production
     alarm_emails = ["ops-team@example.com"]

     # ... existing variables ...
   }
   ```

2. **Confirm SNS subscriptions:**
   - After `terraform apply`, check email for SNS confirmation links
   - Click "Confirm subscription" in each email
   - Alarms won't deliver until confirmed

3. **Review security settings:**
   - `ssh_cidr_block` now defaults to VPC CIDR (no longer 0.0.0.0/0)
   - If you need broader access, explicitly set `ssh_cidr_block`
   - Ensure `cluster_master_count` is odd (1, 3, 5, 7)

### Upgrade Notes

- DNS Lambda functions will be recreated due to module version update
- New SNS topics will be created for alarms
- No security group recreation (typos in Names preserved to avoid disruption)
- Instance refresh may occur for ASG nodes


### 6.2 README.md Alert Section

Add after CloudWatch Logging section:

```markdown
## Alert Configuration

The module includes comprehensive CloudWatch alarm monitoring for cluster health and operational issues.

### Required Configuration

**Email Notifications** are required for ALL environments:

```hcl
module "elasticsearch" {
  source = "infrahouse/elasticsearch/aws"

  alarm_emails = [
    "ops-team@example.com",
    "devops@example.com"
  ]

  # ... other variables
}
```

**IMPORTANT:** After deployment, AWS SNS will send a confirmation email to each address. 
You **MUST** click the confirmation link in each email to activate notifications. 
Unconfirmed subscriptions will not receive alerts.

### What Gets Monitored

The module creates CloudWatch alarms for:

#### Application Load Balancer Health
- **Unhealthy Hosts**: Alerts when cluster nodes fail health checks
- **High Latency**: Alerts when response times exceed thresholds
- **Server Errors**: Alerts when 5xx error rate exceeds success rate threshold
- **CPU Overutilization**: Alerts when autoscaling can't keep up with demand

#### DNS Lambda Functions
- **Lambda Errors**: Alerts on DNS update failures
- **Lambda Throttling**: Alerts when Lambda is rate-limited
- **Lambda Duration**: Alerts on timeout issues

### Advanced Configuration

See the [Inputs](#inputs) section for all alarm configuration variables.

### Cost Implications

**SNS Topics:**
- First 1,000 notifications/month: Free
- Email notifications: Free
- Additional notifications: ~$0.50/1,000

**Typical monthly cost:** $0-5/month depending on alarm frequency.


---

## 7. Risk Assessment & Mitigation

### Minimal Resource Recreation

✅ **Security groups preserved** - Name typos kept to avoid recreation
✅ **Module updates are backward compatible** - No breaking changes in dependencies
✅ **DNS Lambda recreation handled gracefully** - Lifecycle hooks manage DNS updates

### Testing Strategy

- **Phase 1:** `make test-keep` for iterative development
- **Phase 2:** `make test-clean` for full validation
- **Phase 3:** CI runs comprehensive test suite

### Rollback Plan

If issues arise:
1. Pin to v3.12.0 in module reference
2. Run `terraform apply` to downgrade
3. Manual cleanup of SNS topics if needed

---

## 8. What's NOT Included

Based on review findings, these items are **intentionally excluded** to avoid resource recreation:

1. ❌ Security group Name typos (would cause recreation)
2. ❌ Extensive refactoring of repeated code blocks
3. ❌ Variable reordering (cosmetic only)

These can be addressed in a future minor version without breaking changes.

---

## 9. Summary

This v4.0.0 release focuses on:

1. **Alert capabilities** - Primary goal achieved
2. **Dependency updates** - Latest stable versions
3. **Critical bug fixes** - Timeout and TLS issues resolved
4. **Security improvements** - Validation without resource recreation

The plan carefully avoids unnecessary resource recreation while delivering the essential monitoring features requested.

**Estimated Time:** 6-8 hours total
**Risk Level:** Low (backward compatible deps, minimal recreation)
**Testing Coverage:** Comprehensive (unit, integration, multi-provider)
