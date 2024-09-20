resource "aws_security_group" "backend_extra" {
  description = "Elasticsearch ${var.cluster_name} transport"
  name_prefix = "${var.cluster_name}-"
  vpc_id      = data.aws_subnet.selected.vpc_id

  tags = merge(
    {
      Name : "Elasticseach ${var.cluster_name} transport"
    },
    local.default_module_tags
  )
}

resource "aws_vpc_security_group_ingress_rule" "backend_extra_reserved" {
  description                  = "Elasticsearch ${var.cluster_name} transport"
  security_group_id            = aws_security_group.backend_extra.id
  from_port                    = 9300
  to_port                      = 9300
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.backend_extra.id
  tags = merge(
    {
      Name = "Elasticsearch transport"
    },
    local.default_module_tags
  )
}
