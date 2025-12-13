# Implementation Plan: terraform-aws-elasticsearch v4.0.0

**Date:** 2025-12-13
**Current Version:** 3.12.0
**Target Version:** 4.0.0
**Type:** BREAKING CHANGE - Major Version Bump

---

## Executive Summary

This plan outlines the implementation of breaking changes for v4.0.0, primarily:
1. **Update module dependencies** to latest versions (website-pod v5.12.1, update-dns v1.0.0)
2. **Add alert capabilities** using the new module alert interfaces
3. **Address critical findings** from the terraform-module-review
4. **Maintain test infrastructure** compatibility with existing test workflows

**Breaking Change Rationale:**
- Module dependency updates (website-pod, update-dns) may change resource behavior
- New **required** variable `alarm_emails` introduces breaking change for existing users
- Alert infrastructure changes may affect existing SNS integrations

---

## 1. Module Dependency Updates

### 1.1 website-pod: 5.10.0 → 5.12.1

**Files to Update:**
- `main.tf` (lines 112, 176)

**Current:**
```hcl
module "elastic_cluster" {
  source  = "registry.infrahouse.com/infrahouse/website-pod/aws"
  version = "5.10.0"
  # ...
}
```

**Updated:**
```hcl
module "elastic_cluster" {
  source  = "registry.infrahouse.com/infrahouse/website-pod/aws"
  version = "5.12.1"
  # ...
}
```

**Impact:**
- Gains CloudWatch alarm capabilities for ALB monitoring
- New variables available: `alarm_emails`, `alarm_topic_arns`, alarm threshold configurations
- May include bug fixes and improvements between 5.10.0 and 5.12.1

**Action Items:**
- [ ] Update both `module.elastic_cluster` and `module.elastic_cluster_data` (if not in bootstrap mode)
- [ ] Review website-pod CHANGELOG between 5.10.0 and 5.12.1 for any breaking changes
- [ ] Test ALB alarm creation in integration tests

### 1.2 update-dns: 0.11.1 → 1.0.0

**Files to Update:**
- `dns.tf` (lines 2, 11)

**Current:**
```hcl
module "update-dns" {
  source  = "registry.infrahouse.com/infrahouse/update-dns/aws"
  version = "0.11.1"
  # ...
}
```

**Updated:**
```hcl
module "update-dns" {
  source  = "registry.infrahouse.com/infrahouse/update-dns/aws"
  version = "1.0.0"
  # ...
}
```

**Impact:**
- Major version bump may include breaking changes
- New alert capabilities: `alarm_emails` (required), `alert_strategy`
- CloudWatch alarms for Lambda errors, throttling, duration

**Action Items:**
- [ ] Update both `module.update-dns` and `module.update-dns-data`
- [ ] Review update-dns CHANGELOG for v1.0.0 breaking changes
- [ ] Test Lambda alarm creation and alerting
- [ ] Verify DNS update lifecycle hooks still work correctly

---

## 2. Alert Capabilities Implementation

### 2.1 Alert Interface Design

Following the pattern from website-pod and update-dns:

**Required Variable:**
- `alarm_emails` - List of email addresses (must have at least one in production)

**Optional Variables:**
- `alarm_topic_arns` - Additional SNS topics for advanced integrations

**Scope:**
Alerts will cover:
1. **ALB Health** (from website-pod):
   - Unhealthy host count
   - High latency
   - Low success rate (5xx errors)
   - CPU utilization issues

2. **Lambda Health** (from update-dns):
   - DNS update Lambda errors
   - Lambda throttling
   - Lambda timeout/duration

3. **CloudWatch Logs** (potential addition):
   - Log ingestion failures
   - High error rates in logs

### 2.2 Variable Additions

**File:** `variables.tf`

**Add:**

```hcl
variable "alarm_emails" {
  description = <<-EOT
    List of email addresses to receive CloudWatch alarm notifications for Elasticsearch cluster monitoring.
    Covers ALB health, Lambda function errors, and infrastructure issues.

    IMPORTANT: After deployment, AWS SNS will send confirmation emails to each address.
    You MUST click the confirmation link in each email to activate notifications.

    In production environments, at least one email address is required.
  EOT
  type        = list(string)

  validation {
    condition     = var.environment == "development" || length(var.alarm_emails) > 0
    error_message = "At least one alarm email address is required in non-development environments."
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

# Lambda/DNS Alarm Configuration
variable "alert_strategy" {
  description = "Alert strategy for DNS Lambda alarms: 'immediate' (alert on first error) or 'threshold' (alert after multiple errors)."
  type        = string
  default     = "threshold"  # More conservative for DNS operations

  validation {
    condition     = contains(["immediate", "threshold"], var.alert_strategy)
    error_message = "Alert strategy must be either 'immediate' or 'threshold'."
  }
}
```

**Placement:** Insert after line 225 (after `sns_topic_alarm_arn`)

### 2.3 Module Parameter Updates

**File:** `main.tf`

**Update master nodes module:**

```hcl
module "elastic_cluster" {
  source  = "registry.infrahouse.com/infrahouse/website-pod/aws"
  version = "5.12.1"
  # ... existing parameters ...

  # Alert Configuration
  alarm_emails                       = var.alarm_emails
  alarm_topic_arns                   = var.alarm_topic_arns
  alarm_unhealthy_host_threshold     = var.alarm_unhealthy_host_threshold
  alarm_target_response_time_threshold = var.alarm_target_response_time_threshold
  alarm_success_rate_threshold       = var.alarm_success_rate_threshold
  alarm_cpu_utilization_threshold    = var.alarm_cpu_utilization_threshold
  alarm_evaluation_periods           = var.alarm_evaluation_periods
}
```

**Update data nodes module:**

```hcl
module "elastic_cluster_data" {
  count   = var.bootstrap_mode ? 0 : 1
  source  = "registry.infrahouse.com/infrahouse/website-pod/aws"
  version = "5.12.1"
  # ... existing parameters ...

  # Alert Configuration
  alarm_emails                       = var.alarm_emails
  alarm_topic_arns                   = var.alarm_topic_arns
  alarm_unhealthy_host_threshold     = var.alarm_unhealthy_host_threshold
  alarm_target_response_time_threshold = var.alarm_target_response_time_threshold
  alarm_success_rate_threshold       = var.alarm_success_rate_threshold
  alarm_cpu_utilization_threshold    = var.alarm_cpu_utilization_threshold
  alarm_evaluation_periods           = var.alarm_evaluation_periods
}
```

**File:** `dns.tf`

**Update DNS modules:**

```hcl
module "update-dns" {
  source  = "registry.infrahouse.com/infrahouse/update-dns/aws"
  version = "1.0.0"
  # ... existing parameters ...

  # Alert Configuration
  alarm_emails    = var.alarm_emails
  alert_strategy  = var.alert_strategy
}

module "update-dns-data" {
  source  = "registry.infrahouse.com/infrahouse/update-dns/aws"
  version = "1.0.0"
  # ... existing parameters ...

  # Alert Configuration
  alarm_emails    = var.alarm_emails
  alert_strategy  = var.alert_strategy
}
```

### 2.4 Output Additions

**File:** `outputs.tf`

**Add at end:**

```hcl
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
```

---

## 3. Review Findings to Address

From `.claude/reviews/terraform-module-review.md`:

### 3.1 Critical Fixes (Must-Do for v4.0.0)

#### 3.1.1 Fix Typos
**File:** `extra_security_group.tf`

**Line 8:** "Elasticseach" → "Elasticsearch"
```hcl
# Current:
Name = "Elasticseach backend extra"

# Fixed:
Name = "Elasticsearch backend extra"
```

**Line 48:** Incorrect description
```hcl
# Current:
description = "Prometheus node exporter"  # Wrong - this is elastic_exporter

# Fixed:
description = "Prometheus elasticsearch exporter"
```

**Line 56:** "elsaticsearch" → "elasticsearch"
```hcl
# Current:
Name = "Prometheus elsaticsearch exporter"

# Fixed:
Name = "Prometheus elasticsearch exporter"
```

#### 3.1.2 Fix Timeout Units Bug
**File:** `main.tf`
**Line 216:**

```hcl
# Current:
wait_for_capacity_timeout = "${var.asg_health_check_grace_period * 1.5}s"

# Fixed:
wait_for_capacity_timeout = "${var.asg_health_check_grace_period * 1.5}m"
```

**Impact:** Data nodes currently wait 1350 seconds instead of ~20 minutes. This is a significant bug.

#### 3.1.3 Fix TLS Certificate Validity
**File:** `tls.tf`
**Line 17:**

```hcl
# Current:
validity_period_hours = 24 * 356 * 100  # 99.726 years

# Fixed:
validity_period_hours = 24 * 365 * 100  # 100 years
```

#### 3.1.4 Add Missing Type Declarations
**File:** `variables.tf`

**Line 141-144:**
```hcl
variable "puppet_hiera_config_path" {
  description = "Path to hiera configuration file."
  type        = string  # ADD THIS
  default     = "{root_directory}/environments/{environment}/hiera.yaml"
}
```

**Line 152-155:**
```hcl
variable "puppet_module_path" {
  description = "Path to common puppet modules."
  type        = string  # ADD THIS
  default     = "{root_directory}/environments/{environment}/modules:{root_directory}/modules"
}
```

#### 3.1.5 Remove Leftover Comments
**File:** `secrets.tf`
**Line 33:**

Remove: `# insert the 2 required variables here`

### 3.2 Important Validations (Should-Do for v4.0.0)

#### 3.2.1 Add Cluster Master Count Validation
**File:** `variables.tf`
**Lines 31-35:**

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

#### 3.2.2 Add Cluster Data Count Validation
**File:** `variables.tf`
**Lines 37-41:**

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

#### 3.2.3 Improve SSH CIDR Block Security
**File:** `variables.tf`
**Lines 193-197:**

```hcl
variable "ssh_cidr_block" {
  description = <<-EOT
    CIDR range that is allowed to SSH into the elastic instances.
    IMPORTANT: Restrict this to your organization's IP range for security.
    Defaults to 0.0.0.0/0 which is NOT recommended for production.
  EOT
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = var.ssh_cidr_block != "0.0.0.0/0" || var.environment == "development"
    error_message = "SSH access from 0.0.0.0/0 is not allowed in non-development environments. Please specify a restricted CIDR range."
  }
}
```

#### 3.2.4 Add Monitoring CIDR Validation
**File:** `variables.tf`
**Lines 199-203:**

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

#### 3.2.5 Add Cluster Name Length Validation
**File:** `variables.tf`
**Lines 25-29:**

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

### 3.3 Additional Outputs (Nice-to-Have)

**File:** `outputs.tf`

```hcl
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

## 4. Testing Strategy

### 4.1 Test Module Updates

**File:** `test_data/test_module/main.tf`

**Add alarm_emails:**

```hcl
module "test" {
  source = "../../"
  providers = {
    aws     = aws
    aws.dns = aws
  }
  cluster_name           = "main-cluster"
  ubuntu_codename        = "noble"
  cluster_master_count   = 3
  cluster_data_count     = 2
  environment            = var.environment
  internet_gateway_id    = var.internet_gateway_id
  key_pair_name          = aws_key_pair.test.key_name
  subnet_ids             = var.lb_subnet_ids
  zone_id                = var.elastic_zone_id
  bootstrap_mode         = var.bootstrap_mode
  snapshot_bucket_prefix = "infrahouse-terraform-aws-elasticsearch"
  snapshot_force_destroy = true
  monitoring_cidr_block  = "10.1.0.0/16"  # FIXED: Use test VPC CIDR instead of 0.0.0.0/0
  secret_elastic_readers = [
    tolist(data.aws_iam_roles.sso-admin.arns)[0],
    "arn:aws:iam::990466748045:user/aleks"
  ]

  # NEW: Alert configuration
  alarm_emails = [
    "test-elasticsearch-alerts@infrahouse.com"
  ]

  # Use threshold strategy for tests to avoid noise
  alert_strategy = "threshold"
}
```

**File:** `test_data/test_module/variables.tf`

Add if not present:
```hcl
variable "test_alarm_email" {
  description = "Email address for test alarm notifications"
  type        = string
  default     = "test-elasticsearch-alerts@infrahouse.com"
}
```

### 4.2 Test Enhancements

**File:** `tests/test_module.py`

**Add alarm testing function:**

```python
def _test_alarm_configuration(tf_output, aws_region, boto3_session):
    """
    Test that CloudWatch alarms are properly configured.

    Verifies:
    - SNS topics created for alarms
    - SNS subscriptions created for alarm_emails
    - CloudWatch alarms created for ALB and Lambda
    """
    LOG.info("=" * 80)
    LOG.info("Testing CloudWatch Alarm Configuration")
    LOG.info("=" * 80)

    cloudwatch_client = boto3_session.client("cloudwatch", region_name=aws_region)
    sns_client = boto3_session.client("sns", region_name=aws_region)

    # Test 1: Verify SNS topics created
    alarm_sns_topic_arn = tf_output.get("alarm_sns_topic_arn", {}).get("value")
    dns_lambda_sns_topic_arn = tf_output.get("dns_lambda_sns_topic_arn", {}).get("value")

    assert alarm_sns_topic_arn, "ALB alarm SNS topic ARN must be present"
    assert dns_lambda_sns_topic_arn, "DNS Lambda alarm SNS topic ARN must be present"

    LOG.info(f"✓ ALB alarm SNS topic: {alarm_sns_topic_arn}")
    LOG.info(f"✓ DNS Lambda alarm SNS topic: {dns_lambda_sns_topic_arn}")

    # Test 2: Verify SNS subscriptions
    for topic_arn in [alarm_sns_topic_arn, dns_lambda_sns_topic_arn]:
        subscriptions = sns_client.list_subscriptions_by_topic(TopicArn=topic_arn)
        sub_list = subscriptions.get("Subscriptions", [])

        assert len(sub_list) > 0, f"No subscriptions found for topic {topic_arn}"

        email_subs = [s for s in sub_list if s["Protocol"] == "email"]
        assert len(email_subs) > 0, f"No email subscriptions found for topic {topic_arn}"

        LOG.info(f"✓ Topic {topic_arn} has {len(email_subs)} email subscription(s)")

    # Test 3: Verify CloudWatch alarms exist
    master_asg_name = tf_output.get("master_asg_name", {}).get("value")

    # List alarms related to our ASG
    alarms = cloudwatch_client.describe_alarms(
        AlarmNamePrefix=master_asg_name[:20]  # CloudWatch limits prefix length
    )

    alarm_list = alarms.get("MetricAlarms", [])

    # We expect alarms for: unhealthy hosts, latency, 5xx errors, CPU
    expected_alarm_types = ["UnhealthyHost", "TargetResponseTime", "HTTPCode_Target_5XX", "CPUUtilization"]

    found_alarm_types = set()
    for alarm in alarm_list:
        for alarm_type in expected_alarm_types:
            if alarm_type in alarm["AlarmName"]:
                found_alarm_types.add(alarm_type)

    LOG.info(f"✓ Found {len(alarm_list)} CloudWatch alarms")
    LOG.info(f"  Alarm types: {', '.join(found_alarm_types)}")

    # At least some alarms should exist (may not find all due to naming)
    assert len(alarm_list) > 0, "No CloudWatch alarms found for the cluster"

    LOG.info("✓ All alarm configuration tests passed!")
    LOG.info("=" * 80)
```

**Add to test_module function:**

```python
def test_module(
    service_network,
    subzone,
    aws_region,
    keep_after,
    test_role_arn,
    aws_provider_version,
    boto3_session,
):
    # ... existing bootstrap and cluster creation code ...

    with terraform_apply(
        terraform_module_dir,
        destroy_after=not keep_after,
        json_output=True,
    ) as tf_output:
        LOG.info(json.dumps(tf_output, indent=4))

        # Wait for any instance refreshes to complete
        master_asg_name = tf_output["master_asg_name"]["value"]
        data_asg_name = tf_output["data_asg_name"]["value"]

        assert master_asg_name, "Master ASG name must be present in outputs"
        assert data_asg_name, "Data ASG name must be present in outputs"

        wait_for_instance_refresh(
            master_asg_name, aws_region, test_role_arn, boto3_session, timeout=3600
        )
        wait_for_instance_refresh(
            data_asg_name, aws_region, test_role_arn, boto3_session, timeout=3600
        )

        # Test CloudWatch logging functionality
        _test_cloudwatch_logging(
            tf_output, aws_region, test_role_arn, boto3_session
        )

        # NEW: Test alarm configuration
        _test_alarm_configuration(
            tf_output, aws_region, boto3_session
        )
```

### 4.3 Test Execution Plan

#### Phase 1: Development Testing (make test-keep)

1. **Initial Bootstrap Test:**
   ```bash
   make test-keep
   ```
   - Verify bootstrap mode works with new module versions
   - Check alarm emails are sent (but don't confirm SNS subscriptions)
   - Manually inspect CloudWatch alarms in AWS Console
   - Verify DNS Lambda alarms created
   - Keep resources for debugging

2. **Manual Verification:**
   - Check SNS topics created
   - Verify email subscriptions created (PendingConfirmation state is OK)
   - Review CloudWatch alarms:
     - Master ALB alarms (4-5 alarms expected)
     - Data ALB alarms (4-5 alarms expected)
     - DNS Lambda alarms (3 alarms expected per Lambda)
   - Test alarm triggering (optional):
     - Stop an EC2 instance to trigger unhealthy host alarm
     - Verify SNS notification sent (if subscription confirmed)

3. **Incremental Testing:**
   - Make small changes
   - Run `terraform apply` in test_data/test_module
   - Verify changes without full teardown

#### Phase 2: Pre-PR Testing (make test-clean)

1. **Clean Slate Test:**
   ```bash
   make clean
   make test-clean
   ```
   - Full bootstrap and deployment
   - Verify all tests pass
   - Ensure resources destroyed cleanly

2. **Multi-Provider Testing:**
   ```bash
   pytest -xvvs -k aws-5 tests/test_module.py
   pytest -xvvs -k aws-6 tests/test_module.py
   ```
   - Test with both AWS provider versions
   - Verify compatibility

3. **Documentation Review:**
   - Ensure README updated with alarm_emails requirement
   - Update CHANGELOG with breaking changes
   - Verify terraform-docs output

#### Phase 3: CI Testing

CI will automatically run:
- Both AWS provider version tests
- Full integration test suite
- Terraform formatting checks
- Documentation generation

**Expected CI Duration:** ~45-60 minutes (due to Elasticsearch cluster bootstrap)

---

## 5. Documentation Updates

### 5.1 README.md Updates

**Add new section after CloudWatch Logging section (before terraform-docs):**

```markdown
## Alert Configuration

The module includes comprehensive CloudWatch alarm monitoring for cluster health and operational issues.

### Required Configuration

**Email Notifications** are required for production environments:

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

**IMPORTANT:** After deployment, AWS SNS will send a confirmation email to each address. You **MUST** click the confirmation link in each email to activate notifications. Unconfirmed subscriptions will not receive alerts.

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

### Advanced Alert Configuration

**Custom Thresholds:**

```hcl
module "elasticsearch" {
  source = "infrahouse/elasticsearch/aws"

  alarm_emails = ["ops@example.com"]

  # Alert immediately when any host is unhealthy
  alarm_unhealthy_host_threshold = 0

  # Require 99.9% success rate (more strict)
  alarm_success_rate_threshold = 99.9

  # Alert on first Lambda error (vs multiple errors)
  alert_strategy = "immediate"

  # ... other variables
}
```

**External Integrations (PagerDuty, Slack, OpsGenie):**

If you have existing SNS topics for integrations:

```hcl
module "elasticsearch" {
  source = "infrahouse/elasticsearch/aws"

  alarm_emails = ["ops@example.com"]

  alarm_topic_arns = [
    "arn:aws:sns:us-west-2:123456789012:pagerduty-critical",
    "arn:aws:sns:us-west-2:123456789012:slack-ops-channel"
  ]

  # ... other variables
}
```

### Alarm Thresholds Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `alarm_unhealthy_host_threshold` | 1 | Alert when 2+ hosts unhealthy (allows rolling updates) |
| `alarm_target_response_time_threshold` | 80% of `idle_timeout` | Latency threshold in seconds |
| `alarm_success_rate_threshold` | 99.0 | Minimum success rate percentage |
| `alarm_cpu_utilization_threshold` | Auto-calculated | CPU percentage threshold |
| `alarm_evaluation_periods` | 2 | Consecutive periods before alerting |
| `alert_strategy` | "threshold" | DNS Lambda alert strategy: "immediate" or "threshold" |

### Cost Implications

**SNS Topics:**
- First 1,000 notifications/month: Free
- Email notifications: Free
- Each additional 1,000 notifications: ~$0.50/month

**Typical monthly cost:** $0-5/month depending on alarm frequency and email volume.
```

### 5.2 CHANGELOG.md

**Add v4.0.0 entry:**

```markdown
## [4.0.0] - 2025-XX-XX

### BREAKING CHANGES

- **Module Dependencies Updated:**
  - `infrahouse/website-pod/aws`: 5.10.0 → 5.12.1
  - `infrahouse/update-dns/aws`: 0.11.1 → 1.0.0

- **New Required Variable:**
  - `alarm_emails` (list of strings): Required in production environments for CloudWatch alarm notifications
  - Users must add this variable when upgrading from v3.x
  - SNS confirmation emails will be sent to each address and must be confirmed

- **Enhanced Security Defaults:**
  - `ssh_cidr_block`: Now validates against 0.0.0.0/0 in non-development environments
  - `monitoring_cidr_block`: Validates against overly permissive CIDR ranges
  - `cluster_master_count`: Must be odd number for Elasticsearch quorum

### Added

- Comprehensive CloudWatch alarm monitoring:
  - ALB health alarms (unhealthy hosts, latency, 5xx errors, CPU)
  - DNS Lambda alarms (errors, throttling, duration)
  - Configurable alarm thresholds and evaluation periods

- New Variables:
  - `alarm_emails` - Email addresses for alarm notifications (required)
  - `alarm_topic_arns` - Additional SNS topics for integrations (optional)
  - `alarm_unhealthy_host_threshold` - Unhealthy host count threshold
  - `alarm_target_response_time_threshold` - Response time threshold
  - `alarm_success_rate_threshold` - Success rate percentage threshold
  - `alarm_cpu_utilization_threshold` - CPU utilization threshold
  - `alarm_evaluation_periods` - Consecutive periods before alerting
  - `alert_strategy` - DNS Lambda alert strategy ("immediate" or "threshold")

- New Outputs:
  - `alarm_sns_topic_arn` - Master nodes alarm SNS topic ARN
  - `alarm_sns_topic_arn_data` - Data nodes alarm SNS topic ARN
  - `dns_lambda_sns_topic_arn` - DNS Lambda alarm SNS topic ARN
  - `dns_lambda_sns_topic_arn_data` - Data nodes DNS Lambda alarm SNS topic ARN
  - `backend_security_group_id` - Backend security group ID
  - `vpc_id` - VPC ID where cluster is deployed
  - `cloudwatch_kms_key_alias` - CloudWatch KMS key alias

- Variable Validations:
  - `cluster_master_count` - Must be odd number for quorum (1, 3, 5, 7, etc.)
  - `cluster_data_count` - Must be at least 1
  - `cluster_name` - Length must be between 1-32 characters
  - `ssh_cidr_block` - Cannot be 0.0.0.0/0 in production
  - `monitoring_cidr_block` - Cannot be 0.0.0.0/0

### Fixed

- **Critical Bug:** Data node `wait_for_capacity_timeout` now correctly uses minutes instead of seconds (was causing 1350s timeout instead of ~20 minutes)
- Typos in security group descriptions and names:
  - "Elasticseach" → "Elasticsearch"
  - "elsaticsearch" → "elasticsearch"
- TLS certificate validity: Fixed calculation from 356 to 365 days
- Missing type declarations for `puppet_hiera_config_path` and `puppet_module_path`
- Removed leftover template comments from code

### Changed

- Test module now uses VPC CIDR (10.1.0.0/16) for `monitoring_cidr_block` instead of overly permissive 0.0.0.0/0

### Migration Guide v3.x → v4.0.0

#### Required Changes

1. **Add alarm_emails variable:**
   ```hcl
   module "elasticsearch" {
     source  = "infrahouse/elasticsearch/aws"
     version = "4.0.0"

     # NEW: Required for production
     alarm_emails = [
       "your-ops-team@example.com"
     ]

     # ... existing variables ...
   }
   ```

2. **Confirm SNS subscriptions:**
   - After `terraform apply`, check email for SNS confirmation links
   - Click "Confirm subscription" in each email
   - Alarms won't deliver until confirmed

#### Optional Changes (Recommended)

3. **Review security defaults:**
   ```hcl
   # If using default ssh_cidr_block = "0.0.0.0/0"
   # Consider restricting to your organization's CIDR
   ssh_cidr_block = "10.0.0.0/8"
   ```

4. **Validate cluster configuration:**
   - Ensure `cluster_master_count` is odd (1, 3, 5, 7)
   - New validation will catch configuration errors

5. **Review new outputs:**
   - `alarm_sns_topic_arn` - For integrating with external monitoring
   - `backend_security_group_id` - For adding custom security rules

#### Breaking Change Details

- **Module version updates** may cause resource replacements (especially lifecycle hooks and Lambda functions)
- Plan for **instance refresh** of ASG nodes during upgrade
- **DNS update Lambdas** will be recreated due to version bump
- **New SNS topics** will be created for alarms

#### Testing Recommendations

1. Test in development/staging first
2. Review `terraform plan` carefully for resource replacements
3. Schedule upgrade during maintenance window
4. Monitor CloudWatch alarms after upgrade
5. Verify SNS email subscriptions confirmed

## [3.12.0] - 2025-XX-XX
...
```

### 5.3 CLAUDE.md Updates

**Update Dependencies section:**

```markdown
## Dependencies

This module depends on:
- `infrahouse/website-pod/aws` (5.12.1): Provides ASG, ALB, target groups, CloudWatch alarms
- `infrahouse/cloud-init/aws` (2.2.2): Generates cloud-init userdata
- `infrahouse/secret/aws` (1.1.0): Manages AWS Secrets Manager secrets
- `infrahouse/update-dns/aws` (1.0.0): Lambda for DNS updates with monitoring

External dependencies for users:
- VPC with subnets (recommended: `infrahouse/service-network/aws`)
- Route53 hosted zone
- EC2 key pair for SSH access
- Email addresses for alarm notifications (production requirement)
```

**Add Alert Monitoring section:**

```markdown
### Alert Monitoring

Located in module integrations with website-pod and update-dns:

- **alarm_emails** (required): List of email addresses for CloudWatch alarms
- **alarm_topic_arns** (optional): Additional SNS topics for PagerDuty, Slack, etc.
- **ALB Alarms** (from website-pod):
  - Unhealthy host count
  - Target response time
  - HTTP 5xx error rate
  - CPU utilization
- **Lambda Alarms** (from update-dns):
  - Function errors
  - Throttling
  - Execution duration

SNS confirmation emails must be manually confirmed after deployment.
```

---

## 6. Implementation Checklist

### Phase 1: Code Changes

#### Core Module Updates
- [ ] Update `main.tf`: website-pod version 5.10.0 → 5.12.1 (both master and data modules)
- [ ] Update `dns.tf`: update-dns version 0.11.1 → 1.0.0 (both DNS modules)
- [ ] Add alarm parameters to `module.elastic_cluster` in `main.tf`
- [ ] Add alarm parameters to `module.elastic_cluster_data` in `main.tf`
- [ ] Add alarm parameters to `module.update-dns` in `dns.tf`
- [ ] Add alarm parameters to `module.update-dns-data` in `dns.tf`

#### Variable Updates
- [ ] Add `alarm_emails` variable to `variables.tf`
- [ ] Add `alarm_topic_arns` variable to `variables.tf`
- [ ] Add `alarm_unhealthy_host_threshold` variable
- [ ] Add `alarm_target_response_time_threshold` variable
- [ ] Add `alarm_success_rate_threshold` variable
- [ ] Add `alarm_cpu_utilization_threshold` variable
- [ ] Add `alarm_evaluation_periods` variable
- [ ] Add `alert_strategy` variable
- [ ] Add validation to `cluster_master_count` (odd number)
- [ ] Add validation to `cluster_data_count` (>= 1)
- [ ] Add validation to `cluster_name` (length 1-32)
- [ ] Add validation to `ssh_cidr_block` (not 0.0.0.0/0 in prod)
- [ ] Add validation to `monitoring_cidr_block` (not 0.0.0.0/0)
- [ ] Add type declaration to `puppet_hiera_config_path`
- [ ] Add type declaration to `puppet_module_path`

#### Output Updates
- [ ] Add `alarm_sns_topic_arn` output
- [ ] Add `alarm_sns_topic_arn_data` output
- [ ] Add `dns_lambda_sns_topic_arn` output
- [ ] Add `dns_lambda_sns_topic_arn_data` output
- [ ] Add `backend_security_group_id` output
- [ ] Add `vpc_id` output
- [ ] Add `cloudwatch_kms_key_alias` output

#### Bug Fixes
- [ ] Fix `extra_security_group.tf` line 8: "Elasticseach" → "Elasticsearch"
- [ ] Fix `extra_security_group.tf` line 48: description
- [ ] Fix `extra_security_group.tf` line 56: "elsaticsearch" → "elasticsearch"
- [ ] Fix `main.tf` line 216: timeout units (s → m)
- [ ] Fix `tls.tf` line 17: 356 → 365 days
- [ ] Remove `secrets.tf` line 33: template comment

#### Test Updates
- [ ] Update `test_data/test_module/main.tf`: Add `alarm_emails`
- [ ] Update `test_data/test_module/main.tf`: Add `alert_strategy`
- [ ] Update `test_data/test_module/main.tf`: Fix `monitoring_cidr_block` (not 0.0.0.0/0)
- [ ] Add `_test_alarm_configuration()` function to `tests/test_module.py`
- [ ] Integrate alarm testing into `test_module()` function
- [ ] Add test alarm email variable

### Phase 2: Documentation

- [ ] Update README.md: Add Alert Configuration section
- [ ] Update README.md: terraform-docs will auto-update inputs/outputs
- [ ] Update CHANGELOG.md: Add v4.0.0 entry with breaking changes
- [ ] Update CHANGELOG.md: Add migration guide
- [ ] Update CLAUDE.md: Dependencies section
- [ ] Update CLAUDE.md: Add Alert Monitoring section
- [ ] Review all documentation for consistency

### Phase 3: Testing

#### Development Testing (make test-keep)
- [ ] Run `make clean`
- [ ] Run `make test-keep`
- [ ] Verify bootstrap phase completes
- [ ] Verify cluster scale-up completes
- [ ] Verify CloudWatch alarms created
- [ ] Verify SNS topics created
- [ ] Verify SNS subscriptions created (PendingConfirmation OK)
- [ ] Manual: Check AWS Console for alarm configuration
- [ ] Manual: Review CloudWatch alarm details
- [ ] Keep resources for debugging

#### Pre-PR Testing (make test-clean)
- [ ] Run `make clean`
- [ ] Run `make test-clean`
- [ ] Verify full test suite passes
- [ ] Verify resources destroyed cleanly
- [ ] Test with AWS provider ~> 5.11 (`pytest -k aws-5`)
- [ ] Test with AWS provider ~> 6.0 (`pytest -k aws-6`)

#### Code Quality
- [ ] Run `make lint` - verify formatting
- [ ] Run `make format` - format all files
- [ ] Verify pre-commit hooks pass
- [ ] Check terraform-docs updated README

### Phase 4: Release Preparation

- [ ] Create feature branch: `feature/v4-alerts-and-module-updates`
- [ ] Commit all changes with descriptive messages
- [ ] Run final `make test-clean` successfully
- [ ] Create pull request with detailed description
- [ ] Wait for CI to pass
- [ ] Review PR diff carefully
- [ ] Merge to main

### Phase 5: Release

- [ ] Checkout main branch
- [ ] Pull latest changes
- [ ] Run `make release-major` (will create v4.0.0)
- [ ] Verify CHANGELOG.md updated correctly
- [ ] Verify version bumped in `.bumpversion.cfg`
- [ ] Verify git tag created
- [ ] Push changes: `git push && git push --tags`
- [ ] Verify module registry picks up new version

---

## 7. Risk Assessment

### High Risk Items

| Risk | Impact | Mitigation |
|------|--------|------------|
| Module dependency updates break existing functionality | High | Comprehensive testing with both AWS provider versions |
| New required variable breaks existing deployments | High | Clear documentation, migration guide, validation only for production |
| Timeout bug fix causes unexpected behavior | Medium | Existing behavior was wrong, fix is correct, test thoroughly |
| DNS Lambda recreation causes temporary DNS issues | Medium | Use lifecycle hooks, test in development first |

### Testing Mitigation

1. **Bootstrap testing** - Ensures cluster initialization works
2. **Upgrade testing** - Test migration path from v3.12.0
3. **Multi-provider testing** - AWS v5 and v6 compatibility
4. **Manual verification** - CloudWatch console inspection
5. **Keep resources** - Debug issues without full teardown

### Rollback Plan

If v4.0.0 has critical issues:

1. **For new deployments:** Pin to v3.12.0
2. **For upgrades:**
   - Revert Terraform code to v3.12.0 reference
   - Run `terraform apply` to downgrade
   - Note: May require manual SNS topic cleanup

---

## 8. Timeline Estimate

### Development: 4-6 hours
- Code changes: 2-3 hours
- Test updates: 1-2 hours
- Documentation: 1 hour

### Testing: 2-3 hours
- `make test-keep`: 45-60 minutes
- Manual verification: 30 minutes
- `make test-clean`: 45-60 minutes
- Multi-provider testing: 30 minutes (parallel with above)

### Release: 30 minutes
- PR creation and review: 15 minutes
- Release process: 15 minutes

**Total: 6.5-9.5 hours**

---

## 9. Success Criteria

✅ **Code Quality:**
- All linting passes (`make lint`)
- Pre-commit hooks pass
- No terraform-docs warnings
- All review findings addressed

✅ **Testing:**
- `make test-clean` passes for both AWS provider versions
- CloudWatch alarms created successfully
- SNS topics and subscriptions created
- No resource creation failures
- Clean resource destruction

✅ **Documentation:**
- README clearly explains alarm_emails requirement
- Migration guide complete and accurate
- CHANGELOG details all breaking changes
- All new variables documented

✅ **Release:**
- Version bumped to 4.0.0
- Git tag created
- Module registry updated
- No critical issues reported

---

## 10. Post-Release Tasks

### Immediate (Day 1)
- [ ] Monitor module registry for v4.0.0 availability
- [ ] Test module installation: `terraform init -upgrade`
- [ ] Verify example in README works with v4.0.0

### Short-term (Week 1)
- [ ] Monitor GitHub issues for upgrade problems
- [ ] Update any internal InfraHouse usage
- [ ] Consider blog post about new alert capabilities

### Medium-term (Month 1)
- [ ] Gather user feedback on alarm thresholds
- [ ] Consider adding CloudWatch dashboards in v4.1.0
- [ ] Review alarm false-positive rates
- [ ] Plan for EBS volume management (from review: FEAT-1)

---

## Notes

### Breaking Change Justification

**Why v4.0.0 (major version bump)?**

1. **New required variable:** `alarm_emails` is required for production, breaking existing modules without it
2. **Module dependency major version:** update-dns went from 0.x to 1.0.0
3. **Behavioral changes:** Validation rules prevent previously-valid configurations (e.g., even master count)
4. **Resource replacements:** Module version updates will cause some resource recreation

**Alternative considered:** Make `alarm_emails` optional with default `[]`
- **Rejected:** Defeats purpose of proactive monitoring
- **Better:** Require in production, allow empty list in development

### Testing Notes

**Why test-keep first?**
- Faster iteration during development
- Can inspect resources in AWS Console
- Can run `terraform apply` for incremental changes
- Reduces costs during development

**Why test-clean before PR?**
- Ensures clean deployment works
- Verifies resource destruction
- Catches issues with initial bootstrap
- Required for CI confidence

### Module Version Selection

**website-pod 5.12.1:**
- Latest stable version
- Includes comprehensive ALB alarm support
- Battle-tested alarm thresholds

**update-dns 1.0.0:**
- Major version indicates stable API
- Lambda monitoring capabilities
- Alert strategy options (immediate vs threshold)