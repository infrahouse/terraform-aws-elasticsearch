# Production Elasticsearch cluster

A hardened configuration: 3 master nodes and 6 data nodes on memory-optimized
instances, restricted network access, Prometheus scraping, 365-day encrypted log
retention, and alarms routed to both email and existing SNS topics.

## What this example adds over [minimal](../minimal)

| Setting | Why |
|---------|-----|
| `instance_type_master` / `instance_type_data` | Masters hold cluster state only; data nodes need far more RAM |
| `data_nodes_root_volume_size = 500` | Indices live on the root volume - size it for the working set |
| `max_instance_lifetime_days = 90` | Instances are recycled quarterly onto fresh, patched AMIs |
| `ssh_cidr_block` / `monitoring_cidr_block` | No `0.0.0.0/0` - jumphost range for SSH, monitoring range for scraping |
| `cloudwatch_log_retention_days = 365` | ISO/SOC baseline, encrypted with a dedicated KMS key |
| `alarm_topic_arns` | Alarms reach PagerDuty/Slack/OpsGenie in addition to email |
| `secret_elastic_readers` | Named roles can read the elastic password without touching the instances |
| `snapshot_bucket_prefix` | Predictable snapshot bucket name across rebuilds |

## Prerequisites

- A VPC with three private subnets in different availability zones, so master quorum
  survives losing one AZ.
- A Route53 hosted zone. If it lives in a different AWS account, add `assume_role` to
  the `aws.dns` provider in `main.tf`.
- An EC2 key pair, and a jumphost or VPN CIDR to reach the instances.

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars

terraform init
terraform apply            # phase 1: bootstrap_mode = true
```

After the bootstrap apply completes, set `bootstrap_mode = false` in
`terraform.tfvars` and apply again to scale to the full cluster. The second apply
waits for both ASG instance refreshes, which takes 20-40 minutes for this node count.

## After deployment

1. Confirm the SNS subscription emails - unconfirmed addresses receive nothing.
2. Register a snapshot policy against the bucket in the `snapshots_bucket` output.
   See [Operations](https://infrahouse.github.io/terraform-aws-elasticsearch/operations/#snapshots-and-backups).
3. Point Prometheus at the exporters on ports 9100 and 9114.
4. Reference `backend_security_group_id` from client security groups to allow access
   over the load balancers.
