variable "region" {
  description = "AWS region where the Elasticsearch cluster is deployed."
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Name of environment the cluster belongs to."
  type        = string
}

variable "cluster_name" {
  description = "Name of the cluster. Also the prefix of the DNS records and the ASG names."
  type        = string
  default     = "elastic"
}

variable "zone_name" {
  description = <<-EOT
    Route53 hosted zone name that will host the cluster DNS records, with a trailing dot.
    For example, "ci-cd.infrahouse.com.".
  EOT
  type        = string
}

variable "key_pair_name" {
  description = "Name of an existing EC2 key pair deployed on the Elasticsearch instances."
  type        = string
}

variable "subnet_ids" {
  description = <<-EOT
    Private subnets where the load balancers and Elasticsearch instances are created.
    Use at least three subnets in different availability zones so master quorum survives
    an availability zone outage.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnets are required for high availability. Provided: ${length(var.subnet_ids)}"
  }
}

variable "replication_region" {
  description = "AWS region for cross-region replication of the snapshot and access log buckets."
  type        = string
  default     = "us-east-1"
}

variable "admin_cidr_block" {
  description = "CIDR range allowed to SSH into the Elasticsearch instances, e.g. a jumphost subnet."
  type        = string

  validation {
    condition     = !can(regex("^0\\.0\\.0\\.0/0$", var.admin_cidr_block))
    error_message = "admin_cidr_block must not be 0.0.0.0/0. Use the CIDR of your jumphost or VPN."
  }
}

variable "monitoring_cidr_block" {
  description = <<-EOT
    CIDR range allowed to scrape the Prometheus exporters on the instances:
    node_exporter (9100) and elasticsearch_exporter (9114).
  EOT
  type        = string
}

variable "alarm_emails" {
  description = <<-EOT
    Email addresses that receive CloudWatch alarm notifications.
    AWS SNS sends a confirmation email to each address - the subscription is inactive
    until the confirmation link is clicked.
  EOT
  type        = list(string)
}

variable "alarm_topic_arns" {
  description = <<-EOT
    Existing SNS topic ARNs that receive alarm notifications alongside alarm_emails.
    Use for PagerDuty, Slack, or OpsGenie integrations.
  EOT
  type        = list(string)
  default     = []
}

variable "secret_elastic_readers" {
  description = "Role ARNs allowed to read the elastic superuser password from Secrets Manager."
  type        = list(string)
  default     = []
}

variable "bootstrap_mode" {
  description = <<-EOT
    Deploy a single master node that forms a new cluster when true.
    Set to false after the first successful apply to scale out to the full cluster.
  EOT
  type        = bool
  default     = true
}
