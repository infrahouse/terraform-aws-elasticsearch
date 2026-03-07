# Getting started

## Prerequisites

1. **Terraform** >= 1.5
2. **VPC with subnets** -- at least 2 subnets in different availability zones.
   The [infrahouse/service-network/aws](https://registry.terraform.io/modules/infrahouse/service-network/aws/latest)
   module is the easiest way to create these.
3. **Route53 hosted zone** -- the module creates DNS records for cluster endpoints.
4. **EC2 key pair** -- for SSH access to instances.

## Step 1: Create the module

New clusters require a two-phase deployment. Start with `bootstrap_mode = true`:

```hcl
module "elasticsearch" {
  source  = "registry.infrahouse.com/infrahouse/elasticsearch/aws"
  version = "4.1.0"

  providers = {
    aws     = aws
    aws.dns = aws
  }

  cluster_name  = "my-cluster"
  environment   = "production"
  key_pair_name = aws_key_pair.my_key.key_name
  subnet_ids    = module.service-network.subnet_private_ids
  zone_id       = data.aws_route53_zone.main.zone_id

  alarm_emails = ["ops-team@example.com"]

  # Important: use t3.large minimum
  instance_type = "t3.large"

  # Phase 1: bootstrap creates a single master node
  bootstrap_mode = true
}
```

```bash
terraform init
terraform apply
```

This creates a single master node that initializes the cluster, generates security
credentials, and completes the ASG lifecycle hook.

Monitor progress via CloudWatch logs at `/elasticsearch/production/my-cluster`
or SSH into the instance and check `/var/log/cloud-init-output.log`.

## Step 2: Scale to full cluster

Once the bootstrap apply completes, change `bootstrap_mode` to `false`:

```diff
-  bootstrap_mode = true
+  bootstrap_mode = false
```

```bash
terraform apply
```

This scales the master ASG from 1 to 3 nodes and creates 3 data nodes.
Each node joins the existing cluster via the ASG lifecycle hook -- the node
runs `ih-elastic cluster commission-node --complete-lifecycle-action` after
Puppet configures Elasticsearch.

Wait for the instance refreshes to complete. You can monitor them in the
EC2 Auto Scaling console or via CLI:

```bash
aws autoscaling describe-instance-refreshes \
  --auto-scaling-group-name my-cluster
```

## Step 3: Verify the cluster

```bash
# Get the elastic user password from Secrets Manager
ELASTIC_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id "<elastic_secret_id from terraform output>" \
  --query SecretString --output text)

# Check cluster health
curl -u "elastic:${ELASTIC_PASSWORD}" \
  "https://my-cluster.example.com/_cluster/health?pretty"
```

Expected output:

```json
{
  "cluster_name" : "my-cluster",
  "status" : "green",
  "number_of_nodes" : 6,
  "number_of_data_nodes" : 3
}
```

## Endpoints

After deployment, the following HTTPS endpoints are available (all with auto-provisioned
Let's Encrypt certificates):

| Endpoint | Purpose |
|----------|---------|
| `https://{cluster_name}.{zone}` | Primary cluster access (master nodes) |
| `https://{cluster_name}-master.{zone}` | Direct master node access |
| `https://{cluster_name}-data.{zone}` | Direct data node access |

## Puppet roles

The module uses two Puppet roles to configure Elasticsearch:

- **`elastic_master`** -- installed on master nodes. Configures Elasticsearch as a
  master-eligible node with `bootstrap_cluster` fact controlling initial cluster formation.
- **`elastic_data`** -- installed on data nodes. Configures Elasticsearch as a data-only node.

Both roles read custom facts passed via cloud-init userdata to configure:

- Cluster name and node discovery
- `bootstrap.memory_lock` (prevents JVM heap from being swapped)
- TLS certificates for transport and HTTP layers
- CloudWatch log shipping
- Snapshot repository (S3 bucket)

## What's next

- [Configuration](configuration.md) -- customize instance types, node counts, alerting
- [Operations](operations.md) -- manage the cluster with `ih-elastic`
- [Troubleshooting](troubleshooting.md) -- diagnose common issues