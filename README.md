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
  version               = "~> 2.0"
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
  module "test" {
    source  = "registry.infrahouse.com/infrahouse/elasticsearch/aws"
    version = "3.4.0"
    
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

The module creates three endpoints to access the cluster. All three of them are output variables of the module.

* Master nodes: `https://${var.cluster_name}-master.${data.aws_route53_zone.cluster.name}` or `https://${var.cluster_name}.${data.aws_route53_zone.cluster.name}` 
* Data nodes: `https://${var.cluster_name}-data.${data.aws_route53_zone.cluster.name}`
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.5 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.11 |
| <a name="requirement_cloudinit"></a> [cloudinit](#requirement\_cloudinit) | ~> 2.3 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | ~> 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 5.11 |
| <a name="provider_aws.dns"></a> [aws.dns](#provider\_aws.dns) | ~> 5.11 |
| <a name="provider_random"></a> [random](#provider\_random) | ~> 3.6 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | ~> 4.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_ca_cert_secret"></a> [ca\_cert\_secret](#module\_ca\_cert\_secret) | registry.infrahouse.com/infrahouse/secret/aws | ~> 1.0 |
| <a name="module_ca_key_secret"></a> [ca\_key\_secret](#module\_ca\_key\_secret) | registry.infrahouse.com/infrahouse/secret/aws | ~> 1.0 |
| <a name="module_elastic_cluster"></a> [elastic\_cluster](#module\_elastic\_cluster) | registry.infrahouse.com/infrahouse/website-pod/aws | 5.3.0 |
| <a name="module_elastic_cluster_data"></a> [elastic\_cluster\_data](#module\_elastic\_cluster\_data) | registry.infrahouse.com/infrahouse/website-pod/aws | 5.3.0 |
| <a name="module_elastic_data_userdata"></a> [elastic\_data\_userdata](#module\_elastic\_data\_userdata) | registry.infrahouse.com/infrahouse/cloud-init/aws | 1.18.0 |
| <a name="module_elastic_master_userdata"></a> [elastic\_master\_userdata](#module\_elastic\_master\_userdata) | registry.infrahouse.com/infrahouse/cloud-init/aws | 1.18.0 |
| <a name="module_update-dns"></a> [update-dns](#module\_update-dns) | registry.infrahouse.com/infrahouse/update-dns/aws | 0.9.1 |
| <a name="module_update-dns-data"></a> [update-dns-data](#module\_update-dns-data) | registry.infrahouse.com/infrahouse/update-dns/aws | 0.9.1 |

## Resources

| Name | Type |
|------|------|
| [aws_autoscaling_lifecycle_hook.launching-data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_lifecycle_hook) | resource |
| [aws_autoscaling_lifecycle_hook.launching-master](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_lifecycle_hook) | resource |
| [aws_autoscaling_lifecycle_hook.terminating-data](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_lifecycle_hook) | resource |
| [aws_autoscaling_lifecycle_hook.terminating-master](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_lifecycle_hook) | resource |
| [aws_s3_bucket.snapshots-bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_public_access_block.public_access](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_secretsmanager_secret.elastic](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret.kibana_system](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.elastic](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_secretsmanager_secret_version.kibana_system](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
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
| [aws_ami.ubuntu](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.elastic_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.secrets-permission-policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
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
| <a name="input_cluster_data_count"></a> [cluster\_data\_count](#input\_cluster\_data\_count) | Number of data nodes in the cluster | `number` | `3` | no |
| <a name="input_cluster_master_count"></a> [cluster\_master\_count](#input\_cluster\_master\_count) | Number of master nodes in the cluster | `number` | `3` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | How to name the cluster | `string` | `"elastic"` | no |
| <a name="input_data_nodes_root_volume_size"></a> [data\_nodes\_root\_volume\_size](#input\_data\_nodes\_root\_volume\_size) | Root volume size in data EC2 instance in Gigabytes | `number` | `30` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Name of environment. | `string` | `"development"` | no |
| <a name="input_extra_files"></a> [extra\_files](#input\_extra\_files) | Additional files to create on an instance. | <pre>list(object({<br/>    content     = string<br/>    path        = string<br/>    permissions = string<br/>  }))</pre> | `[]` | no |
| <a name="input_extra_instance_profile_permissions"></a> [extra\_instance\_profile\_permissions](#input\_extra\_instance\_profile\_permissions) | A JSON with a permissions policy document. The policy will be attached to the ASG instance profile. | `string` | `null` | no |
| <a name="input_extra_repos"></a> [extra\_repos](#input\_extra\_repos) | Additional APT repositories to configure on an instance. | <pre>map(object({<br/>    source = string<br/>    key    = string<br/>  }))</pre> | `{}` | no |
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
| <a name="output_cluster_data_load_balancer_arn"></a> [cluster\_data\_load\_balancer\_arn](#output\_cluster\_data\_load\_balancer\_arn) | ARN of the load balancer for the cluster data nodes |
| <a name="output_cluster_data_url"></a> [cluster\_data\_url](#output\_cluster\_data\_url) | HTTPS endpoint to access the cluster data nodes |
| <a name="output_cluster_master_load_balancer_arn"></a> [cluster\_master\_load\_balancer\_arn](#output\_cluster\_master\_load\_balancer\_arn) | ARN of the load balancer for the cluster masters |
| <a name="output_cluster_master_url"></a> [cluster\_master\_url](#output\_cluster\_master\_url) | HTTPS endpoint to access the cluster masters |
| <a name="output_cluster_url"></a> [cluster\_url](#output\_cluster\_url) | HTTPS endpoint to access the cluster |
| <a name="output_data_instance_role_arn"></a> [data\_instance\_role\_arn](#output\_data\_instance\_role\_arn) | Data node EC2 instance profile will have this role ARN |
| <a name="output_elastic_password"></a> [elastic\_password](#output\_elastic\_password) | Password for Elasticsearch superuser elastic. |
| <a name="output_elastic_secret_id"></a> [elastic\_secret\_id](#output\_elastic\_secret\_id) | AWS secret that stores password for user elastic. |
| <a name="output_idle_timeout_data"></a> [idle\_timeout\_data](#output\_idle\_timeout\_data) | The amount of time a client or target connection can be idle before the load balancer (that fronts data nodes) closes it. |
| <a name="output_idle_timeout_master"></a> [idle\_timeout\_master](#output\_idle\_timeout\_master) | The amount of time a client or target connection can be idle before the load balancer (that fronts master nodes) closes it. |
| <a name="output_kibana_system_password"></a> [kibana\_system\_password](#output\_kibana\_system\_password) | A password of kibana\_system user |
| <a name="output_kibana_system_secret_id"></a> [kibana\_system\_secret\_id](#output\_kibana\_system\_secret\_id) | AWS secret that stores password for user kibana\_system |
| <a name="output_master_instance_role_arn"></a> [master\_instance\_role\_arn](#output\_master\_instance\_role\_arn) | Master node EC2 instance profile will have this role ARN |
| <a name="output_snapshots_bucket"></a> [snapshots\_bucket](#output\_snapshots\_bucket) | AWS S3 Bucket where Elasticsearch snapshots will be stored. |
