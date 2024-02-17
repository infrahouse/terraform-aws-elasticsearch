module "test" {
  source = "../../"
  providers = {
    aws     = aws
    aws.dns = aws
  }
  cluster_name         = "main-cluster"
  cluster_master_count = 3
  cluster_data_count   = 1
  environment          = var.environment
  internet_gateway_id  = module.service-network.internet_gateway_id
  key_pair_name        = aws_key_pair.test.key_name
  subnet_ids           = module.service-network.subnet_public_ids
  zone_id              = var.elastic_zone_id
  bootstrap_mode       = false
}
