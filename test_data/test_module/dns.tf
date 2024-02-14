resource "random_string" "elastic_subdomain" {
  length  = 6
  numeric = false
  special = false
  upper   = false
}

resource "aws_route53_zone" "elastic" {
  name = "${random_string.elastic_subdomain.result}.${data.aws_route53_zone.cicd.name}"
}

resource "aws_route53_record" "elastic-ns" {
  name    = aws_route53_zone.elastic.name
  type    = "NS"
  zone_id = data.aws_route53_zone.cicd.zone_id
  ttl     = 172800
  records = aws_route53_zone.elastic.name_servers
}
