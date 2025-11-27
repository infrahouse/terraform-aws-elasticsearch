# terraform-aws-elasticsearch

The module deploys a multi-node Elasticsearch cluster.

# Usage

## Dependencies

The module requires several additional components that are needed
to provision the Elasticsearch cluster.

* At least two subnets to place a load balancer and autoscaling group.
* Route53 zone - the cluster will have an HTTPS endpoint for the cluster.

### Service network

The easiest way to create subnets in AWS is to use
the [Service Network](https://registry.terraform.io/modules/infrahouse/service-network/aws/latest) Terraform module.

Typical configuration would include at least two public and two private subnets.

```hcl
module "service-network" {
  source                = "infrahouse/service-network/aws"
  version               = "~> 3.2"
  service_name          = "elastic"
  vpc_cidr_block        = "10.1.0.0/16"
  management_cidr_block = "10.1.0.0/16"
  subnets = [
    {
      cidr                    = "10.1.0.0/24"
      availability-zone       = data.aws_availability_zones.available.names[0]
      map_public_ip_on_launch = true
      create_nat              = true
      forward_to              = null
    },
    {
      cidr                    = "10.1.1.0/24"
      availability-zone       = data.aws_availability_zones.available.names[1]
      map_public_ip_on_launch = true
      create_nat              = true
      forward_to              = null
    },
    {
      cidr                    = "10.1.2.0/24"
      availability-zone       = data.aws_availability_zones.available.names[0]
      map_public_ip_on_launch = false
      create_nat              = false
      forward_to              = "10.1.0.0/24"
    },
    {
      cidr                    = "10.1.3.0/24"
      availability-zone       = data.aws_availability_zones.available.names[1]
      map_public_ip_on_launch = false
      create_nat              = false
      forward_to              = "10.1.1.0/24"
    }
  ]
}
```
### Route53 Zone
The module will create an A record for the cluster in a specified zone.
If the cluster name (passed as `var.cluster_name`) is 'elastic', the client URL
is going to be https://elastic.ci-cd.infrahouse.com.
The zone can be created in the same Terraform module or accessed as a data source.
```hcl
data "aws_route53_zone" "cicd" {
  name = "ci-cd.infrahouse.com"
}
```
## Bootstrapping cluster

Any new cluster needs to be bootstrapped first. Let's say we want to create a three node cluster.
Declare the cluster and add `bootstrap_mode = true` to the module inputs.
The size of the autoscaling group will be not three, but one node.
```hcl
module "test" {
  source  = "registry.infrahouse.com/infrahouse/elasticsearch/aws"
  version = "3.11.0"

  providers = {
    aws     = aws
    aws.dns = aws
  }
  internet_gateway_id = module.service-network.internet_gateway_id
  key_pair_name       = aws_key_pair.test.key_name
  subnet_ids          = module.service-network.subnet_public_ids
  zone_id             = data.aws_route53_zone.cicd.zone_id
  bootstrap_mode      = true
}
```

## Provisioning remaining nodes

After the cluster is bootstrapped, disable the bootstrap mode.
```hcl
diff --git a/test_data/test_module/main.tf b/test_data/test_module/main.tf
index c13df0d..33cf0d3 100644
--- a/test_data/test_module/main.tf
+++ b/test_data/test_module/main.tf
@@ -12,5 +12,5 @@ module "test" {
   subnet_ids                    = module.service-network.subnet_private_ids
   zone_id                       = data.aws_route53_zone.cicd.zone_id
-  bootstrap_mode                = true
+  bootstrap_mode                = false
 }
```

## Accessing the cluster

The module creates HTTPS endpoints to access different parts of the Elasticsearch cluster. All endpoints are available as output variables.

### Endpoints

* **Cluster endpoint**: ``https://${var.cluster_name}.${data.aws_route53_zone.cluster.name}``
    - Primary endpoint for general cluster access
    - Points to master nodes
* **Master nodes**: ``https://${var.cluster_name}-master.${data.aws_route53_zone.cluster.name}``
    - Direct access to master nodes
    - Used for cluster management operations
* **Data nodes**: ``https://${var.cluster_name}-data.${data.aws_route53_zone.cluster.name}``
    - Direct access to data nodes
    - Used for search and indexing operations

All endpoints use HTTPS with automatically provisioned SSL certificates.

## CloudWatch Logging

The module includes integrated CloudWatch Logs support for centralized log aggregation and monitoring of your Elasticsearch cluster.

### Overview

CloudWatch logging is **enabled by default** and provides:
- Centralized log storage for all cluster nodes (master and data)
- KMS encryption at rest for log data
- Configurable retention periods
- Integration with CloudWatch Insights for log analysis
- Automatic log stream creation per instance

### Default Configuration

When enabled (default), the module creates:
- **CloudWatch Log Group**: `/elasticsearch/${var.environment}/${var.cluster_name}`
  - Example: `/elasticsearch/production/main-cluster`
- **KMS Key**: Customer-managed key with automatic rotation for log encryption
- **IAM Permissions**: Least-privilege permissions for instances to write logs
- **Log Retention**: 365 days (configurable via `cloudwatch_log_retention_days`, minimum 365 for compliance)
- **Key Rotation**: 365 days (configurable via `cloudwatch_kms_rotation_period_days`)

### Cost Implications

CloudWatch Logs pricing consists of:
1. **Data Ingestion**: ~$0.50 per GB ingested
2. **Storage**: ~$0.03 per GB per month
3. **KMS Key**: ~$1.00 per month per key

**Estimated Monthly Costs** (approximate, varies by region and usage):
- Small cluster (3 nodes, ~5 GB/month logs): **$3.50-$5.00/month**
- Medium cluster (6 nodes, ~15 GB/month logs): **$8.50-$10.00/month**
- Large cluster (12+ nodes, ~50 GB/month logs): **$26.50-$30.00/month**

**Cost optimization tips**:
- Retention period is fixed at 365 days minimum for compliance requirements
- Consider using log filtering and CloudWatch Logs Insights queries to reduce data ingestion
- Archive older logs to S3 Glacier for long-term storage at lower cost

### Configuration Variables

Control CloudWatch logging behavior with these variables:

```hcl
module "elasticsearch" {
  source = "infrahouse/elasticsearch/aws"

  # CloudWatch Logging Configuration
  enable_cloudwatch_logging          = true  # Enable/disable CloudWatch logging (default: true)
  cloudwatch_log_retention_days      = 365   # Log retention period in days (default: 365, minimum: 365)
  cloudwatch_kms_rotation_period_days = 365  # KMS key rotation period (default: 365)

  # ... other variables
}
```

See the [Inputs](#inputs) section below for complete variable documentation.

### Disabling CloudWatch Logging

To disable CloudWatch logging (not recommended for production):

```hcl
module "elasticsearch" {
  source = "infrahouse/elasticsearch/aws"

  enable_cloudwatch_logging = false

  # ... other variables
}
```

**Note**: Disabling CloudWatch logging removes centralized log visibility and may impact troubleshooting capabilities.

### Accessing Logs

After deployment, access logs through:

1. **AWS Console**:
   - Navigate to CloudWatch → Log groups
   - Find log group: `/elasticsearch/${environment}/${cluster_name}`
   - Each instance creates its own log stream

2. **AWS CLI**:
   ```bash
   # List recent log streams
   aws logs describe-log-streams \
     --log-group-name "/elasticsearch/production/main-cluster" \
     --order-by LastEventTime \
     --descending \
     --max-items 10

   # Tail logs in real-time
   aws logs tail "/elasticsearch/production/main-cluster" --follow
   ```

3. **CloudWatch Insights**:
   - Use CloudWatch Logs Insights for advanced log queries
   - Example query to find errors:
     ```
     fields @timestamp, @message
     | filter @message like /ERROR/
     | sort @timestamp desc
     | limit 100
     ```

### Outputs

The module provides these CloudWatch-related outputs:

- `cloudwatch_log_group_name`: Name of the CloudWatch log group
- `cloudwatch_log_group_arn`: ARN of the CloudWatch log group
- `cloudwatch_kms_key_id`: ID of the KMS key used for log encryption
- `cloudwatch_kms_key_arn`: ARN of the KMS key used for log encryption

See the [Outputs](#outputs) section below for complete output documentation.

### Integration with Existing Clusters

CloudWatch logging can be added to existing clusters:

1. **Add the configuration** to your Terraform module
2. **Apply the changes** - The module will:
   - Create the CloudWatch log group and KMS key
   - Update instance IAM roles with logging permissions
   - Refresh instances to pick up the new configuration (via instance refresh)
3. **Verify logging** - Check the CloudWatch console for new log streams

**Note**: Instance refresh will cause a rolling replacement of instances, planned to minimize disruption.

### Security

CloudWatch logging follows security best practices:
- **Encryption at Rest**: All logs encrypted with customer-managed KMS key
- **Key Rotation**: Automatic annual key rotation enabled by default
- **Least Privilege IAM**: Instances can only write logs, not read them
- **Write-Only Access**: Instances cannot read logs from CloudWatch (read access requires separate permissions)

### Monitoring and Alarms

Consider setting up CloudWatch alarms for:
- High error rates in logs
- Missing log streams (indicating instance issues)
- Log ingestion rate anomalies

Example alarm configuration is not included but can be added using the `cloudwatch_log_group_name` output.

<!-- BEGIN_TF_DOCS -->

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.5 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.11, < 7.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.11, < 7.0 |
| <a name="provider_aws.dns"></a> [aws.dns](#provider\_aws.dns) | >= 5.11, < 7.0 |
| <a name="provider_random"></a> [random](#provider\_random) | ~> 3.6 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | ~> 4.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_ca_cert_secret"></a> [ca\_cert\_secret](#module\_ca\_cert\_secret) | registry.infrahouse.com/infrahouse/secret/aws | ~> 1.0 |
| <a name="module_ca_key_secret"></a> [ca\_key\_secret](#module\_ca\_key\_secret) | registry.infrahouse.com/infrahouse/secret/aws | ~> 1.0 |
| <a name="module_elastic-password"></a> [elastic-password](#module\_elastic-password) | registry.infrahouse.com/infrahouse/secret/aws | 1.1.0 |
| <a name="module_elastic_cluster"></a> [elastic\_cluster](#module\_elastic\_cluster) | registry.infrahouse.com/infrahouse/website-pod/aws | 5.10.0 |
| <a name="module_elastic_cluster_data"></a> [elastic\_cluster\_data](#module\_elastic\_cluster\_data) | registry.infrahouse.com/infrahouse/website-pod/aws | 5.10.0 |
| <a name="module_elastic_data_userdata"></a> [elastic\_data\_userdata](#module\_elastic\_data\_userdata) | registry.infrahouse.com/infrahouse/cloud-init/aws | 2.2.2 |
| <a name="module_elastic_master_userdata"></a> [elastic\_master\_userdata](#module\_elastic\_master\_userdata) | registry.infrahouse.com/infrahouse/cloud-init/aws | 2.2.2 |
| <a name="module_kibana_system-password"></a> [kibana\_system-password](#module\_kibana\_system-password) | registry.infrahouse.com/infrahouse/secret/aws | 1.1.0 |
| <a name="module_update-dns"></a> [update-dns](#module\_update-dns) | registry.infrahouse.com/infrahouse/update-dns/aws | 0.11.1 |
| <a name="module_update-dns-data"></a> [update-dns-data](#module\_update-dns-data) | registry.infrahouse.com/infrahouse/update-dns/aws | 0.11.1 |

## Resources

| Name | Type |
|------|------|
| [aws_autoscaling_lifecycle_hook.launching-data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_lifecycle_hook) | resource |
| [aws_autoscaling_lifecycle_hook.launching-master](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_lifecycle_hook) | resource |
| [aws_autoscaling_lifecycle_hook.terminating-data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_lifecycle_hook) | resource |
| [aws_autoscaling_lifecycle_hook.terminating-master](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_lifecycle_hook) | resource |
| [aws_cloudwatch_log_group.elasticsearch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_kms_alias.cloudwatch_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.cloudwatch_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_kms_key_policy.cloudwatch_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key_policy) | resource |
| [aws_s3_bucket.snapshots-bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_policy.snapshots-bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.public_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_security_group.backend_extra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_ingress_rule.backend_extra_reserved](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.elastic_exporter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.node_exporter](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [random_password.elastic](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.kibana_system](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_string.bucket_prefix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [random_string.launching_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [random_string.profile-suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/string) | resource |
| [tls_private_key.ca_key](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/private_key) | resource |
| [tls_self_signed_cert.ca_cert](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/resources/self_signed_cert) | resource |
| [aws_ami.ubuntu_pro](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.bucket_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.cloudwatch_logs_key_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.cloudwatch_logs_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.elastic_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_role.caller_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_role) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_route53_zone.cluster](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone) | data source |
| [aws_subnet.selected](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_asg_ami"></a> [asg\_ami](#input\_asg\_ami) | Image for EC2 instances | `string` | `null` | no |
| <a name="input_asg_create_initial_lifecycle_hook"></a> [asg\_create\_initial\_lifecycle\_hook](#input\_asg\_create\_initial\_lifecycle\_hook) | Used for migration from version 1.* | `bool` | `true` | no |
| <a name="input_asg_health_check_grace_period"></a> [asg\_health\_check\_grace\_period](#input\_asg\_health\_check\_grace\_period) | ASG will wait up to this number of seconds for instance to become healthy | `number` | `900` | no |
| <a name="input_bootstrap_mode"></a> [bootstrap\_mode](#input\_bootstrap\_mode) | Set this to true if the cluster is to be bootstrapped | `bool` | `true` | no |
| <a name="input_cloudwatch_kms_rotation_period_days"></a> [cloudwatch\_kms\_rotation\_period\_days](#input\_cloudwatch\_kms\_rotation\_period\_days) | Number of days between automatic KMS key rotations for CloudWatch logs encryption | `number` | `90` | no |
| <a name="input_cloudwatch_log_retention_days"></a> [cloudwatch\_log\_retention\_days](#input\_cloudwatch\_log\_retention\_days) | CloudWatch log retention in days (minimum 365 days required for compliance) | `number` | `365` | no |
| <a name="input_cluster_data_count"></a> [cluster\_data\_count](#input\_cluster\_data\_count) | Number of data nodes in the cluster | `number` | `3` | no |
| <a name="input_cluster_master_count"></a> [cluster\_master\_count](#input\_cluster\_master\_count) | Number of master nodes in the cluster | `number` | `3` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | How to name the cluster | `string` | `"elastic"` | no |
| <a name="input_data_nodes_root_volume_size"></a> [data\_nodes\_root\_volume\_size](#input\_data\_nodes\_root\_volume\_size) | Root volume size in data EC2 instance in Gigabytes | `number` | `30` | no |
| <a name="input_enable_cloudwatch_logging"></a> [enable\_cloudwatch\_logging](#input\_enable\_cloudwatch\_logging) | Enable CloudWatch logging for the Elasticsearch cluster | `bool` | `true` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Name of environment. | `string` | `"development"` | no |
| <a name="input_extra_files"></a> [extra\_files](#input\_extra\_files) | Additional files to create on an instance. | <pre>list(object({<br/>    content     = string<br/>    path        = string<br/>    permissions = string<br/>  }))</pre> | `[]` | no |
| <a name="input_extra_instance_profile_permissions"></a> [extra\_instance\_profile\_permissions](#input\_extra\_instance\_profile\_permissions) | A JSON with a permissions policy document. The policy will be attached to the ASG instance profile. | `string` | `null` | no |
| <a name="input_extra_repos"></a> [extra\_repos](#input\_extra\_repos) | Additional APT repositories to configure on an instance. | <pre>map(<br/>    object(<br/>      {<br/>        source   = string<br/>        key      = string<br/>        machine  = optional(string)<br/>        authFrom = optional(string)<br/>        priority = optional(number)<br/>      }<br/>    )<br/>  )</pre> | `{}` | no |
| <a name="input_idle_timeout_data"></a> [idle\_timeout\_data](#input\_idle\_timeout\_data) | The amount of time a client or target connection can be idle before the load balancer (that fronts data nodes) closes it. | `number` | `4000` | no |
| <a name="input_idle_timeout_master"></a> [idle\_timeout\_master](#input\_idle\_timeout\_master) | The amount of time a client or target connection can be idle before the load balancer (that fronts master nodes) closes it. | `number` | `4000` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | Instance type to run the elasticsearch node | `string` | `"t3.medium"` | no |
| <a name="input_instance_type_data"></a> [instance\_type\_data](#input\_instance\_type\_data) | Instance type to run the elasticsearch data node. If null, use var.instance\_type. | `string` | `null` | no |
| <a name="input_instance_type_master"></a> [instance\_type\_master](#input\_instance\_type\_master) | Instance type to run the elasticsearch master node. If null, use var.instance\_type. | `string` | `null` | no |
| <a name="input_internet_gateway_id"></a> [internet\_gateway\_id](#input\_internet\_gateway\_id) | Not used, but AWS Internet Gateway must be present. Ensure by passing its id. | `string` | n/a | yes |
| <a name="input_key_pair_name"></a> [key\_pair\_name](#input\_key\_pair\_name) | SSH keypair name to be deployed in EC2 instances | `string` | n/a | yes |
| <a name="input_master_nodes_root_volume_size"></a> [master\_nodes\_root\_volume\_size](#input\_master\_nodes\_root\_volume\_size) | Root volume size in master EC2 instance in Gigabytes | `number` | `null` | no |
| <a name="input_max_instance_lifetime_days"></a> [max\_instance\_lifetime\_days](#input\_max\_instance\_lifetime\_days) | The maximum amount of time, in \_days\_, that an instance can be in service, values must be either equal to 0 or between 7 and 365 days. | `number` | `0` | no |
| <a name="input_monitoring_cidr_block"></a> [monitoring\_cidr\_block](#input\_monitoring\_cidr\_block) | CIDR range that is allowed to monitor elastic instances. | `string` | `null` | no |
| <a name="input_packages"></a> [packages](#input\_packages) | List of packages to install when the instances bootstraps. | `list(string)` | `[]` | no |
| <a name="input_puppet_debug_logging"></a> [puppet\_debug\_logging](#input\_puppet\_debug\_logging) | Enable debug logging if true. | `bool` | `false` | no |
| <a name="input_puppet_environmentpath"></a> [puppet\_environmentpath](#input\_puppet\_environmentpath) | A path for directory environments. | `string` | `"{root_directory}/environments"` | no |
| <a name="input_puppet_hiera_config_path"></a> [puppet\_hiera\_config\_path](#input\_puppet\_hiera\_config\_path) | Path to hiera configuration file. | `string` | `"{root_directory}/environments/{environment}/hiera.yaml"` | no |
| <a name="input_puppet_manifest"></a> [puppet\_manifest](#input\_puppet\_manifest) | Path to puppet manifest. By default ih-puppet will apply {root\_directory}/environments/{environment}/manifests/site.pp. | `string` | `null` | no |
| <a name="input_puppet_module_path"></a> [puppet\_module\_path](#input\_puppet\_module\_path) | Path to common puppet modules. | `string` | `"{root_directory}/environments/{environment}/modules:{root_directory}/modules"` | no |
| <a name="input_secret_elastic_readers"></a> [secret\_elastic\_readers](#input\_secret\_elastic\_readers) | List of role ARNs that will have permissions to read elastic superuser secret. | `list(string)` | `null` | no |
| <a name="input_smtp_credentials_secret"></a> [smtp\_credentials\_secret](#input\_smtp\_credentials\_secret) | AWS secret name with SMTP credentials. The secret must contain a JSON with user and password keys. | `string` | `null` | no |
| <a name="input_snapshot_bucket_prefix"></a> [snapshot\_bucket\_prefix](#input\_snapshot\_bucket\_prefix) | A string prefix to a bucket name for snapshots. Random by default. | `string` | `null` | no |
| <a name="input_snapshot_force_destroy"></a> [snapshot\_force\_destroy](#input\_snapshot\_force\_destroy) | Destroy S3 bucket with Elasticsearch snapshots even if non-empty | `bool` | `false` | no |
| <a name="input_sns_topic_alarm_arn"></a> [sns\_topic\_alarm\_arn](#input\_sns\_topic\_alarm\_arn) | ARN of SNS topic for Cloudwatch alarms on base EC2 instance. | `string` | `null` | no |
| <a name="input_ssh_cidr_block"></a> [ssh\_cidr\_block](#input\_ssh\_cidr\_block) | CIDR range that is allowed to SSH into the elastic instances. | `string` | `"0.0.0.0/0"` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | List of subnet ids where the elasticsearch instances will be created | `list(string)` | n/a | yes |
| <a name="input_ubuntu_codename"></a> [ubuntu\_codename](#input\_ubuntu\_codename) | Ubuntu version to use for the elasticsearch node | `string` | `"jammy"` | no |
| <a name="input_zone_id"></a> [zone\_id](#input\_zone\_id) | Domain name zone ID where the website will be available | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cloudwatch_kms_key_arn"></a> [cloudwatch\_kms\_key\_arn](#output\_cloudwatch\_kms\_key\_arn) | ARN of the KMS key used for CloudWatch log encryption |
| <a name="output_cloudwatch_kms_key_id"></a> [cloudwatch\_kms\_key\_id](#output\_cloudwatch\_kms\_key\_id) | ID of the KMS key used for CloudWatch log encryption |
| <a name="output_cloudwatch_log_group_arn"></a> [cloudwatch\_log\_group\_arn](#output\_cloudwatch\_log\_group\_arn) | ARN of the CloudWatch log group for Elasticsearch logs |
| <a name="output_cloudwatch_log_group_name"></a> [cloudwatch\_log\_group\_name](#output\_cloudwatch\_log\_group\_name) | Name of the CloudWatch log group for Elasticsearch logs |
| <a name="output_cluster_data_load_balancer_arn"></a> [cluster\_data\_load\_balancer\_arn](#output\_cluster\_data\_load\_balancer\_arn) | ARN of the load balancer for the cluster data nodes |
| <a name="output_cluster_data_ssl_listener_arn"></a> [cluster\_data\_ssl\_listener\_arn](#output\_cluster\_data\_ssl\_listener\_arn) | ARN of cluster data ssl listener of balancer |
| <a name="output_cluster_data_target_group_arn"></a> [cluster\_data\_target\_group\_arn](#output\_cluster\_data\_target\_group\_arn) | ARN of the target group for the cluster data nodes |
| <a name="output_cluster_data_url"></a> [cluster\_data\_url](#output\_cluster\_data\_url) | HTTPS endpoint to access the cluster data nodes |
| <a name="output_cluster_master_load_balancer_arn"></a> [cluster\_master\_load\_balancer\_arn](#output\_cluster\_master\_load\_balancer\_arn) | ARN of the load balancer for the cluster masters |
| <a name="output_cluster_master_ssl_listener_arn"></a> [cluster\_master\_ssl\_listener\_arn](#output\_cluster\_master\_ssl\_listener\_arn) | ARN of cluster masters ssl listener of balancer |
| <a name="output_cluster_master_target_group_arn"></a> [cluster\_master\_target\_group\_arn](#output\_cluster\_master\_target\_group\_arn) | ARN of the target group for the cluster master nodes |
| <a name="output_cluster_master_url"></a> [cluster\_master\_url](#output\_cluster\_master\_url) | HTTPS endpoint to access the cluster masters |
| <a name="output_cluster_url"></a> [cluster\_url](#output\_cluster\_url) | HTTPS endpoint to access the cluster |
| <a name="output_data_asg_name"></a> [data\_asg\_name](#output\_data\_asg\_name) | Name of the Auto Scaling Group for data nodes |
| <a name="output_data_instance_role_arn"></a> [data\_instance\_role\_arn](#output\_data\_instance\_role\_arn) | Data node EC2 instance profile will have this role ARN |
| <a name="output_elastic_password"></a> [elastic\_password](#output\_elastic\_password) | Password for Elasticsearch superuser elastic. |
| <a name="output_elastic_secret_id"></a> [elastic\_secret\_id](#output\_elastic\_secret\_id) | AWS secret that stores password for user elastic. |
| <a name="output_idle_timeout_data"></a> [idle\_timeout\_data](#output\_idle\_timeout\_data) | The amount of time a client or target connection can be idle before the load balancer (that fronts data nodes) closes it. |
| <a name="output_idle_timeout_master"></a> [idle\_timeout\_master](#output\_idle\_timeout\_master) | The amount of time a client or target connection can be idle before the load balancer (that fronts master nodes) closes it. |
| <a name="output_kibana_system_password"></a> [kibana\_system\_password](#output\_kibana\_system\_password) | A password of kibana\_system user |
| <a name="output_kibana_system_secret_id"></a> [kibana\_system\_secret\_id](#output\_kibana\_system\_secret\_id) | AWS secret that stores password for user kibana\_system |
| <a name="output_master_asg_name"></a> [master\_asg\_name](#output\_master\_asg\_name) | Name of the Auto Scaling Group for master nodes |
| <a name="output_master_instance_role_arn"></a> [master\_instance\_role\_arn](#output\_master\_instance\_role\_arn) | Master node EC2 instance profile will have this role ARN |
| <a name="output_snapshots_bucket"></a> [snapshots\_bucket](#output\_snapshots\_bucket) | AWS S3 Bucket where Elasticsearch snapshots will be stored. |
<!-- END_TF_DOCS -->
