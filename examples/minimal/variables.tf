variable "region" {
  description = "AWS region where the Elasticsearch cluster is deployed."
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Name of environment the cluster belongs to."
  type        = string
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
    Subnets where the load balancers and Elasticsearch instances are created.
    At least two subnets in different availability zones are required.
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

variable "alarm_emails" {
  description = <<-EOT
    Email addresses that receive CloudWatch alarm notifications.
    AWS SNS sends a confirmation email to each address - the subscription is inactive
    until the confirmation link is clicked.
  EOT
  type        = list(string)
}

variable "bootstrap_mode" {
  description = <<-EOT
    Deploy a single master node that forms a new cluster when true.
    Set to false after the first successful apply to scale out to the full cluster.
  EOT
  type        = bool
  default     = true
}
