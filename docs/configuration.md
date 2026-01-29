# Configuration

Complete reference for all module variables organized by category.

## Required Variables

These variables must be provided:

| Variable | Type | Description |
|----------|------|-------------|
| `key_pair_name` | `string` | SSH keypair name to be deployed in EC2 instances |
| `subnet_ids` | `list(string)` | List of subnet IDs where Elasticsearch instances will be created |
| `zone_id` | `string` | Route53 zone ID for DNS records |

## Cluster Configuration

### Basic Settings

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `cluster_name` | `string` | `"elastic"` | Name of the Elasticsearch cluster |
| `environment` | `string` | `"development"` | Environment name (e.g., production, staging) |
| `bootstrap_mode` | `bool` | `true` | Set to `true` for initial cluster bootstrap, `false` after |

### Node Counts

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `cluster_master_count` | `number` | `3` | Number of master nodes (must be odd for quorum) |
| `cluster_data_count` | `number` | `3` | Number of data nodes |

### Instance Types

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `instance_type` | `string` | `"t3.medium"` | Default instance type for all nodes |
| `instance_type_master` | `string` | `null` | Override instance type for master nodes |
| `instance_type_data` | `string` | `null` | Override instance type for data nodes |

### Storage

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `master_nodes_root_volume_size` | `number` | `null` | Root volume size (GB) for master nodes |
| `data_nodes_root_volume_size` | `number` | `30` | Root volume size (GB) for data nodes |

## Networking

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ssh_cidr_block` | `string` | `"0.0.0.0/0"` | CIDR range allowed to SSH into instances |
| `monitoring_cidr_block` | `string` | `null` | CIDR range allowed to monitor instances (Prometheus) |

## Load Balancer

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `idle_timeout_master` | `number` | `4000` | Idle timeout (seconds) for master nodes ALB |
| `idle_timeout_data` | `number` | `4000` | Idle timeout (seconds) for data nodes ALB |

## CloudWatch Logging

CloudWatch logging is enabled by default for centralized log management.

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_cloudwatch_logging` | `bool` | `true` | Enable CloudWatch logging |
| `cloudwatch_log_retention_days` | `number` | `365` | Log retention period (minimum 365 for compliance) |
| `cloudwatch_kms_rotation_period_days` | `number` | `90` | KMS key rotation period |

### Log Group Location

Logs are stored at: `/elasticsearch/${environment}/${cluster_name}`

### Accessing Logs

```bash
# List log streams
aws logs describe-log-streams \
  --log-group-name "/elasticsearch/production/my-cluster" \
  --order-by LastEventTime --descending

# Tail logs
aws logs tail "/elasticsearch/production/my-cluster" --follow
```

## Alerting

### Email Notifications

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `alarm_emails` | `list(string)` | `[]` | Email addresses for CloudWatch alarm notifications |
| `alarm_topic_arns` | `list(string)` | `[]` | Additional SNS topic ARNs (PagerDuty, Slack, etc.) |

!!! warning "Email Confirmation Required"
    After deployment, AWS SNS sends confirmation emails to each address.
    You must click the confirmation link to activate notifications.

### Alarm Thresholds

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `alarm_unhealthy_host_threshold` | `number` | `1` | Unhealthy hosts before alerting (0 = immediate) |
| `alarm_target_response_time_threshold` | `number` | `null` | Response time threshold (defaults to 80% of idle_timeout) |
| `alarm_success_rate_threshold` | `number` | `99` | Minimum success rate percentage |
| `alarm_cpu_utilization_threshold` | `number` | `null` | CPU threshold (defaults to autoscaling target + 30%) |
| `alarm_evaluation_periods` | `number` | `2` | Consecutive periods before alerting |
| `alarm_success_rate_period` | `number` | `300` | Time window for success rate (60, 300, 900, or 3600) |

### Example: PagerDuty Integration

```hcl
module "elasticsearch" {
  # ...

  alarm_emails     = ["ops@example.com"]
  alarm_topic_arns = [aws_sns_topic.pagerduty.arn]
}
```

## Security

### Secrets Management

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `secret_elastic_readers` | `list(string)` | `null` | IAM role ARNs allowed to read elastic user secret |

The module automatically creates secrets for:

- `elastic` superuser password
- `kibana_system` user password
- TLS CA certificate and key

### SMTP Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `smtp_credentials_secret` | `string` | `null` | AWS Secrets Manager secret name with SMTP credentials |

The SMTP secret must contain JSON with `user` and `password` keys.

## Snapshots

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `snapshot_bucket_prefix` | `string` | `null` | S3 bucket name prefix (random if not specified) |
| `snapshot_force_destroy` | `bool` | `false` | Allow destroying non-empty snapshot bucket |

## Auto Scaling

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `asg_health_check_grace_period` | `number` | `900` | Seconds to wait for instance health |
| `max_instance_lifetime_days` | `number` | `0` | Max instance lifetime (0 = unlimited, or 7-365) |

## Puppet Configuration

The module uses Puppet for instance configuration:

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `puppet_debug_logging` | `bool` | `false` | Enable Puppet debug logging |
| `puppet_environmentpath` | `string` | `"{root_directory}/environments"` | Puppet environment path |
| `puppet_hiera_config_path` | `string` | `"{root_directory}/environments/{environment}/hiera.yaml"` | Hiera config path |
| `puppet_manifest` | `string` | `null` | Custom Puppet manifest path |
| `puppet_module_path` | `string` | See defaults | Puppet module search path |

## Advanced

### Additional Instance Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `packages` | `list(string)` | `[]` | Additional packages to install |
| `extra_files` | `list(object)` | `[]` | Additional files to create on instances |
| `extra_repos` | `map(object)` | `{}` | Additional APT repositories |
| `extra_instance_profile_permissions` | `string` | `null` | Additional IAM permissions JSON |

### Example: Extra Files

```hcl
module "elasticsearch" {
  # ...

  extra_files = [
    {
      content     = "custom configuration"
      path        = "/etc/elasticsearch/custom.yml"
      permissions = "0644"
    }
  ]
}
```

### AMI Configuration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `asg_ami` | `string` | `null` | Custom AMI ID (defaults to Ubuntu Pro) |
| `ubuntu_codename` | `string` | `"jammy"` | Ubuntu version codename |

## Complete Example

```hcl
module "elasticsearch" {
  source  = "registry.infrahouse.com/infrahouse/elasticsearch/aws"
  version = "4.0.0"

  providers = {
    aws     = aws
    aws.dns = aws
  }

  # Required
  key_pair_name = "my-keypair"
  subnet_ids    = module.vpc.private_subnet_ids
  zone_id       = data.aws_route53_zone.main.zone_id

  # Cluster settings
  cluster_name         = "production-es"
  environment          = "production"
  bootstrap_mode       = false
  cluster_master_count = 3
  cluster_data_count   = 5

  # Instance types
  instance_type_master = "r6i.large"
  instance_type_data   = "r6i.2xlarge"

  # Storage
  data_nodes_root_volume_size = 500

  # Alerting
  alarm_emails     = ["ops@example.com", "oncall@example.com"]
  alarm_topic_arns = [aws_sns_topic.pagerduty.arn]

  # Security
  ssh_cidr_block        = "10.0.0.0/8"
  monitoring_cidr_block = "10.0.0.0/8"
}
```