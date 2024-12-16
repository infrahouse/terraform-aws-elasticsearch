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


resource "aws_vpc_security_group_ingress_rule" "node_exporter" {
  count             = var.monitoring_cidr_block == null ? 0 : 1
  description       = "Prometheus node exporter"
  security_group_id = aws_security_group.backend_extra.id
  from_port         = 9100
  to_port           = 9100
  ip_protocol       = "tcp"
  cidr_ipv4         = var.monitoring_cidr_block
  tags = merge(
    {
      Name = "Prometheus node exporter"
    },
    local.default_module_tags
  )
}

resource "aws_vpc_security_group_ingress_rule" "elastic_exporter" {
  count             = var.monitoring_cidr_block == null ? 0 : 1
  description       = "Prometheus node exporter"
  security_group_id = aws_security_group.backend_extra.id
  from_port         = 9114
  to_port           = 9114
  ip_protocol       = "tcp"
  cidr_ipv4         = var.monitoring_cidr_block
  tags = merge(
    {
      Name = "Prometheus elsaticsearch exporter"
    },
    local.default_module_tags
  )
}
