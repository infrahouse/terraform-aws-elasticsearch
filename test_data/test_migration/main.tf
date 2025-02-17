# Initial state
# module "test" {
#   source  = "infrahouse/elasticsearch/aws"
#   version = "< 2.0.0"
#   providers = {
#     aws     = aws
#     aws.dns = aws
#   }
#   cluster_name           = "main-cluster"
#   cluster_master_count   = 3
#   cluster_data_count     = 2
#   environment            = "sandbox"
#   internet_gateway_id    = var.internet_gateway_id
#   key_pair_name          = aws_key_pair.test.key_name
#   subnet_ids             = var.lb_subnet_ids
#   zone_id                = var.elastic_zone_id
#   bootstrap_mode         = var.bootstrap_mode
#   snapshot_bucket_prefix = "infrahouse-terraform-aws-elasticsearch"
#   snapshot_force_destroy = true
#   monitoring_cidr_block  = "0.0.0.0/0"
#   secret_elastic_readers = [
#     "arn:aws:iam::${data.aws_caller_identity.this.account_id}:role/aws-reserved/sso.amazonaws.com/us-west-1/AWSReservedSSO_AWSAdministratorAccess_422821c726d81c14",
#     "arn:aws:iam::990466748045:user/aleks"
#   ]
# }

# Migration
module "test" {
  source = "../../"
  providers = {
    aws     = aws
    aws.dns = aws
  }
  asg_create_initial_lifecycle_hook = false
  cluster_name                      = "main-cluster"
  cluster_master_count              = 3
  cluster_data_count                = 2
  environment                       = "sandbox"
  internet_gateway_id               = var.internet_gateway_id
  key_pair_name                     = aws_key_pair.test.key_name
  subnet_ids                        = var.lb_subnet_ids
  zone_id                           = var.elastic_zone_id
  bootstrap_mode                    = var.bootstrap_mode
  snapshot_bucket_prefix            = "infrahouse-terraform-aws-elasticsearch"
  snapshot_force_destroy            = true
  monitoring_cidr_block             = "0.0.0.0/0"
  secret_elastic_readers = [
    "arn:aws:iam::${data.aws_caller_identity.this.account_id}:role/aws-reserved/sso.amazonaws.com/us-west-1/AWSReservedSSO_AWSAdministratorAccess_422821c726d81c14",
    "arn:aws:iam::990466748045:user/aleks"
  ]
}
