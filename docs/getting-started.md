# Getting Started

This guide walks you through deploying your first Elasticsearch cluster using this module.

## Prerequisites

Before you begin, ensure you have:

1. **Terraform** >= 1.5 installed
2. **AWS CLI** configured with appropriate credentials
3. **VPC with subnets** - at least 2 subnets in different availability zones
4. **Route53 hosted zone** - for DNS record management
5. **EC2 key pair** - for SSH access to instances

## Step 1: Create the VPC Infrastructure

If you don't have existing VPC infrastructure, use the
[infrahouse/service-network/aws](https://registry.terraform.io/modules/infrahouse/service-network/aws/latest)
module:

```hcl
module "service-network" {
  source  = "registry.infrahouse.com/infrahouse/service-network/aws"
  version = "3.2.1"

  service_name          = "elasticsearch"
  vpc_cidr_block        = "10.1.0.0/16"
  management_cidr_block = "10.1.0.0/16"

  subnets = [
    {
      cidr                    = "10.1.0.0/24"
      availability-zone       = "us-west-2a"
      map_public_ip_on_launch = true
      create_nat              = true
      forward_to              = null
    },
    {
      cidr                    = "10.1.1.0/24"
      availability-zone       = "us-west-2b"
      map_public_ip_on_launch = true
      create_nat              = true
      forward_to              = null
    },
    {
      cidr                    = "10.1.2.0/24"
      availability-zone       = "us-west-2a"
      map_public_ip_on_launch = false
      create_nat              = false
      forward_to              = "10.1.0.0/24"
    },
    {
      cidr                    = "10.1.3.0/24"
      availability-zone       = "us-west-2b"
      map_public_ip_on_launch = false
      create_nat              = false
      forward_to              = "10.1.1.0/24"
    }
  ]
}
```

## Step 2: Reference Your Route53 Zone

```hcl
data "aws_route53_zone" "main" {
  name = "example.com"
}
```

## Step 3: Create an EC2 Key Pair

```hcl
resource "aws_key_pair" "elasticsearch" {
  key_name   = "elasticsearch-key"
  public_key = file("~/.ssh/id_rsa.pub")
}
```

## Step 4: Deploy in Bootstrap Mode

New clusters must be bootstrapped before scaling to full size. Create the module with
`bootstrap_mode = true`:

```hcl
module "elasticsearch" {
  source  = "registry.infrahouse.com/infrahouse/elasticsearch/aws"
  version = "4.0.0"

  providers = {
    aws     = aws
    aws.dns = aws
  }

  cluster_name  = "my-cluster"
  environment   = "production"
  key_pair_name = aws_key_pair.elasticsearch.key_name
  subnet_ids    = module.service-network.subnet_private_ids
  zone_id       = data.aws_route53_zone.main.zone_id

  alarm_emails = ["ops-team@example.com"]

  # Bootstrap mode - creates single master node
  bootstrap_mode = true
}
```

Apply the configuration:

```bash
terraform init
terraform plan
terraform apply
```

Wait for the bootstrap to complete. The initial master node will:

1. Initialize the Elasticsearch cluster
2. Set up security credentials
3. Complete the Auto Scaling lifecycle hook

You can monitor progress in the EC2 console or via CloudWatch logs.

## Step 5: Scale to Full Cluster

Once bootstrap completes, disable bootstrap mode:

```hcl
module "elasticsearch" {
  # ... same configuration as above ...

  # Disable bootstrap mode to scale up
  bootstrap_mode = false
}
```

Apply the changes:

```bash
terraform apply
```

This will:

1. Scale master nodes from 1 to 3 (default)
2. Create 3 data nodes (default)
3. All nodes join the existing cluster

## Step 6: Verify the Cluster

After deployment, access your cluster:

```bash
# Get the elastic user password from AWS Secrets Manager
ELASTIC_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id "<elastic_secret_id from outputs>" \
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
  "number_of_data_nodes" : 3,
  ...
}
```

## Endpoints

After deployment, the following endpoints are available:

| Endpoint | Purpose |
|----------|---------|
| `https://${cluster_name}.${zone}` | Primary cluster access (master nodes) |
| `https://${cluster_name}-master.${zone}` | Direct master node access |
| `https://${cluster_name}-data.${zone}` | Direct data node access |

## Next Steps

- [Configuration](configuration.md) - Customize cluster settings
- Review CloudWatch alarms and confirm SNS email subscriptions
- Set up Kibana for visualization (separate deployment)
- Configure index lifecycle policies