# terraform-aws-elasticsearch

Terraform module that deploys a multi-node Elasticsearch cluster on AWS with high availability,
automatic scaling, and enterprise-grade security.

## Features

- **Multi-node Architecture**: Separate master and data node pools for optimal performance
- **High Availability**: Deploys across multiple availability zones with automatic failover
- **Auto Scaling**: Configurable Auto Scaling Groups for both master and data nodes
- **Load Balancing**: Application Load Balancers with HTTPS endpoints for secure access
- **Security**: TLS encryption, AWS Secrets Manager integration, and least-privilege IAM policies
- **Monitoring**: CloudWatch logging with KMS encryption and configurable alarms
- **DNS Integration**: Automatic Route53 DNS record management
- **Snapshot Support**: S3 bucket for Elasticsearch snapshots with proper access controls

## Quick Start

```hcl
module "elasticsearch" {
  source  = "registry.infrahouse.com/infrahouse/elasticsearch/aws"
  version = "~> 4.0"

  providers = {
    aws     = aws
    aws.dns = aws
  }

  cluster_name    = "my-cluster"
  environment     = "production"
  key_pair_name   = "my-keypair"
  subnet_ids      = ["subnet-abc123", "subnet-def456"]
  zone_id         = "Z1234567890ABC"

  alarm_emails = ["ops@example.com"]

  # Start in bootstrap mode for new clusters
  bootstrap_mode = true
}
```

After the initial bootstrap completes, set `bootstrap_mode = false` and apply again to scale
to the full cluster size.

## Architecture

The module creates a two-tier Elasticsearch cluster:

```
                    ┌─────────────────────────────────────────────────┐
                    │                   Route53                       │
                    │  cluster.example.com → Master ALB               │
                    │  cluster-data.example.com → Data ALB            │
                    └─────────────────────────────────────────────────┘
                                          │
                    ┌─────────────────────┴─────────────────────┐
                    │                                           │
              ┌─────▼─────┐                               ┌─────▼─────┐
              │ Master ALB│                               │  Data ALB │
              └─────┬─────┘                               └─────┬─────┘
                    │                                           │
         ┌──────────┼──────────┐                     ┌──────────┼──────────┐
         │          │          │                     │          │          │
    ┌────▼───┐ ┌────▼───┐ ┌────▼───┐            ┌────▼───┐ ┌────▼───┐ ┌────▼───┐
    │Master 1│ │Master 2│ │Master 3│            │ Data 1 │ │ Data 2 │ │ Data 3 │
    └────────┘ └────────┘ └────────┘            └────────┘ └────────┘ └────────┘
         │          │          │                     │          │          │
         └──────────┴──────────┴─────────────────────┴──────────┴──────────┘
                              Elasticsearch Cluster
```

### Master Nodes

- Handle cluster management, metadata, and shard allocation
- Default: 3 nodes (configurable via `cluster_master_count`)
- Accessible via `https://${cluster_name}.${zone}` and `https://${cluster_name}-master.${zone}`

### Data Nodes

- Handle indexing and search operations
- Default: 3 nodes (configurable via `cluster_data_count`)
- Accessible via `https://${cluster_name}-data.${zone}`
- Only deployed when `bootstrap_mode = false`

## Requirements

| Name | Version |
|------|---------|
| Terraform | >= 1.5 |
| AWS Provider | >= 5.11, < 7.0 |

## Next Steps

- [Getting Started](getting-started.md) - Prerequisites and first deployment
- [Configuration](configuration.md) - Complete variable reference
