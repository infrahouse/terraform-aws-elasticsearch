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
  source = "../../"
  providers = {
    aws     = aws
    aws.dns = aws
  }
  cluster_name                  = "main-cluster"
  cluster_size                  = 3
  internet_gateway_id           = module.service-network.internet_gateway_id
  key_pair_name                 = aws_key_pair.test.key_name
  subnet_ids                    = module.service-network.subnet_public_ids
  zone_id                       = data.aws_route53_zone.cicd.zone_id
  asg_health_check_grace_period = 3600 * 24
  bootstrap_mode                = true
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
   asg_health_check_grace_period = 3600 * 24
-  bootstrap_mode                = true
+  bootstrap_mode                = false
 }
```


## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.5 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.11 |
| <a name="requirement_cloudinit"></a> [cloudinit](#requirement\_cloudinit) | ~> 2.3 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 5.11 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_elastic_cluster"></a> [elastic\_cluster](#module\_elastic\_cluster) | infrahouse/website-pod/aws | ~> 2.6 |
| <a name="module_elastic_master_userdata"></a> [elastic\_master\_userdata](#module\_elastic\_master\_userdata) | infrahouse/cloud-init/aws | ~> 1.8 |

## Resources

| Name | Type |
|------|------|
| [aws_security_group.backend_extra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_ingress_rule.backend_extra_reserved](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_ami.ubuntu](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.elastic_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_subnet.selected](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_asg_health_check_grace_period"></a> [asg\_health\_check\_grace\_period](#input\_asg\_health\_check\_grace\_period) | ASG will wait up to this number of seconds for instance to become healthy | `number` | `300` | no |
| <a name="input_bootstrap_mode"></a> [bootstrap\_mode](#input\_bootstrap\_mode) | Set this to true if the cluster is to be bootstrapped | `bool` | `true` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | How to name the cluster | `string` | `"elastic"` | no |
| <a name="input_cluster_size"></a> [cluster\_size](#input\_cluster\_size) | Number of nodes in the cluster | `number` | `3` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Name of environment. | `string` | `"development"` | no |
| <a name="input_extra_files"></a> [extra\_files](#input\_extra\_files) | Additional files to create on an instance. | <pre>list(object({<br>    content     = string<br>    path        = string<br>    permissions = string<br>  }))</pre> | `[]` | no |
| <a name="input_extra_repos"></a> [extra\_repos](#input\_extra\_repos) | Additional APT repositories to configure on an instance. | <pre>map(object({<br>    source = string<br>    key    = string<br>  }))</pre> | `{}` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | Instance type to run the elasticsearch node | `string` | `"t3.medium"` | no |
| <a name="input_internet_gateway_id"></a> [internet\_gateway\_id](#input\_internet\_gateway\_id) | Not used, but AWS Internet Gateway must be present. Ensure by passing its id. | `string` | n/a | yes |
| <a name="input_key_pair_name"></a> [key\_pair\_name](#input\_key\_pair\_name) | SSH keypair name to be deployed in EC2 instances | `string` | n/a | yes |
| <a name="input_packages"></a> [packages](#input\_packages) | List of packages to install when the instances bootstraps. | `list(string)` | `[]` | no |
| <a name="input_puppet_debug_logging"></a> [puppet\_debug\_logging](#input\_puppet\_debug\_logging) | Enable debug logging if true. | `bool` | `false` | no |
| <a name="input_puppet_hiera_config_path"></a> [puppet\_hiera\_config\_path](#input\_puppet\_hiera\_config\_path) | Path to hiera configuration file. | `string` | `"{root_directory}/environments/{environment}/hiera.yaml"` | no |
| <a name="input_puppet_module_path"></a> [puppet\_module\_path](#input\_puppet\_module\_path) | Path to common puppet modules. | `string` | `"{root_directory}/modules"` | no |
| <a name="input_puppet_root_directory"></a> [puppet\_root\_directory](#input\_puppet\_root\_directory) | Path where the puppet code is hosted. | `string` | `"/opt/puppet-code"` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | List of subnet ids where the elasticsearch instances will be created | `list(string)` | n/a | yes |
| <a name="input_ubuntu_codename"></a> [ubuntu\_codename](#input\_ubuntu\_codename) | Ubuntu version to use for the elasticsearch node | `string` | `"jammy"` | no |
| <a name="input_zone_id"></a> [zone\_id](#input\_zone\_id) | Domain name zone ID where the website will be available | `string` | n/a | yes |

## Outputs

No outputs.
