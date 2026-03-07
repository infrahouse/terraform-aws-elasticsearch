# Configuration

All variables are documented in the
[README](https://github.com/infrahouse/terraform-aws-elasticsearch#inputs)
via terraform-docs. This page covers the most important settings with guidance
on how to choose values.

## Instance sizing

The single most important configuration decision. Elasticsearch needs memory for
two things: the JVM heap and the Lucene filesystem cache. The rule of thumb is
**give ES half the RAM for heap, leave the other half for filesystem cache**.

```hcl
# Minimum viable configuration
instance_type = "t3.large"  # 8 GB -- enough for light workloads

# Production: size master and data nodes independently
instance_type_master = "r6i.large"    # 16 GB -- masters are lighter
instance_type_data   = "r6i.xlarge"   # 32 GB -- data nodes need more for Lucene cache
```

!!! danger "memory_lock and instance sizing"
    With `memory_lock = true` (the default), the JVM heap is locked in physical RAM
    and cannot be swapped. The instance **must** have enough RAM for heap + OS + Lucene cache,
    or the OOM killer will terminate Elasticsearch.

    On a `t3.medium` (4 GB), this leaves only ~0.8 GB free after the ~1.9 GB heap is locked.
    Any memory spike will trigger an OOM kill. Use `t3.large` (8 GB) at minimum.

See the [instance sizing table](index.md#instance-sizing) for detailed recommendations.

### Storage

```hcl
# Master nodes: default is fine (they store metadata, not data)
master_nodes_root_volume_size = null  # uses AMI default

# Data nodes: size based on your index size + overhead
data_nodes_root_volume_size = 100  # GB, default is 30
```

## Cluster sizing

```hcl
# Master nodes: must be odd for quorum (1, 3, 5)
cluster_master_count = 3  # default, recommended for production

# Data nodes: scale based on indexing/search throughput
cluster_data_count = 3    # default
```

For a single-environment test cluster, 3 masters + 3 data nodes is a good starting point.
For production with heavy indexing, consider 3 masters + 5-9 data nodes.

## Memory lock

```hcl
# Prevents JVM heap from being swapped to disk (default: true)
memory_lock = true
```

When enabled, Puppet configures:

- `bootstrap.memory_lock: true` in `elasticsearch.yml`
- `LimitMEMLOCK=infinity` in the systemd override

This eliminates GC pauses caused by swapped heap pages. Without it, GC must page
memory back from disk, turning 50ms pauses into multi-second pauses that make the
node unresponsive.

Set to `false` only if you understand the swap implications and have a specific reason.

## Bootstrap mode

```hcl
# Phase 1: initial cluster creation (single master node)
bootstrap_mode = true

# Phase 2: scale to full cluster (change and re-apply)
bootstrap_mode = false
```

See [Getting Started](getting-started.md) for the full bootstrap workflow.

## Networking

```hcl
# Subnets for ES instances (at least 2 AZs for HA)
subnet_ids = module.service-network.subnet_private_ids

# SSH access (restrict in production)
ssh_cidr_block = "10.0.0.0/8"

# Prometheus monitoring access (node_exporter + elasticsearch_exporter)
monitoring_cidr_block = "10.0.0.0/8"  # null = disabled
```

## Load balancer

```hcl
# Idle timeout in seconds -- Elasticsearch queries can be slow
idle_timeout_master = 4000  # default
idle_timeout_data   = 4000  # default
```

The high default (4000s / ~66 min) accommodates long-running queries, scroll contexts,
and reindexing operations. Reduce if your workload has shorter request lifetimes.

## CloudWatch logging

Enabled by default. Creates a log group at `/elasticsearch/{environment}/{cluster_name}`
with KMS encryption.

```hcl
enable_cloudwatch_logging          = true  # default
cloudwatch_log_retention_days      = 365   # minimum for compliance
cloudwatch_kms_rotation_period_days = 90   # KMS key rotation
```

To disable (not recommended for production):

```hcl
enable_cloudwatch_logging = false
```

## Alerting

At least one alarm email is required:

```hcl
alarm_emails = ["ops@example.com"]

# Optional: forward to PagerDuty, Slack, etc.
alarm_topic_arns = [aws_sns_topic.pagerduty.arn]
```

!!! note "Email confirmation required"
    After deployment, AWS SNS sends confirmation emails. You must click the
    confirmation link in each email to activate notifications.

### Alarm thresholds

All thresholds have sensible defaults. Override only if needed:

```hcl
alarm_unhealthy_host_threshold         = 1     # alert when 2+ hosts unhealthy
alarm_target_response_time_threshold   = null  # defaults to 80% of idle_timeout
alarm_success_rate_threshold           = 99.0  # minimum non-5xx rate
alarm_cpu_utilization_threshold        = null  # defaults to autoscaling target + 30%
alarm_evaluation_periods               = 2     # consecutive periods before alerting
alarm_success_rate_period              = 300   # window in seconds
```

## Secrets

The module auto-generates passwords for `elastic` and `kibana_system` users and
stores them in AWS Secrets Manager.

```hcl
# Grant additional IAM roles read access to the elastic password
secret_elastic_readers = [
  "arn:aws:iam::123456789012:role/app-role"
]
```

## Snapshots

```hcl
# Custom bucket prefix (random if not specified)
snapshot_bucket_prefix = "my-cluster-snapshots"

# Allow terraform destroy to delete non-empty bucket
snapshot_force_destroy = false  # default, set true for test environments
```

## Complete production example

```hcl
module "elasticsearch" {
  source  = "registry.infrahouse.com/infrahouse/elasticsearch/aws"
  version = "4.1.0"

  providers = {
    aws     = aws
    aws.dns = aws
  }

  # Required
  key_pair_name = "production-key"
  subnet_ids    = module.vpc.private_subnet_ids
  zone_id       = data.aws_route53_zone.main.zone_id

  # Cluster
  cluster_name         = "production-es"
  environment          = "production"
  bootstrap_mode       = false
  cluster_master_count = 3
  cluster_data_count   = 5

  # Instance sizing
  instance_type_master = "r6i.large"
  instance_type_data   = "r6i.xlarge"
  data_nodes_root_volume_size = 500

  # Security
  ssh_cidr_block        = "10.0.0.0/8"
  monitoring_cidr_block = "10.0.0.0/8"

  # Alerting
  alarm_emails     = ["ops@example.com", "oncall@example.com"]
  alarm_topic_arns = [aws_sns_topic.pagerduty.arn]
}
```