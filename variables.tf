variable "asg_ami" {
  description = "Image for EC2 instances"
  type        = string
  default     = null
}

variable "asg_health_check_grace_period" {
  description = "ASG will wait up to this number of seconds for instance to become healthy"
  type        = number
  default     = 900
}

variable "asg_create_initial_lifecycle_hook" {
  description = "Used for migration from version 1.*"
  type        = bool
  default     = true
}

variable "bootstrap_mode" {
  description = "Set this to true if the cluster is to be bootstrapped"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "How to name the cluster"
  type        = string
  default     = "elastic"

  validation {
    condition     = length(var.cluster_name) >= 1 && length(var.cluster_name) <= 32
    error_message = "cluster_name must be between 1 and 32 characters for ALB name_prefix compatibility."
  }
}

variable "cluster_master_count" {
  description = "Number of master nodes in the cluster (must be odd for quorum)"
  type        = number
  default     = 3

  validation {
    condition     = var.cluster_master_count % 2 == 1
    error_message = "cluster_master_count must be an odd number for Elasticsearch quorum (e.g., 1, 3, 5, 7)."
  }

  validation {
    condition     = var.cluster_master_count >= 1
    error_message = "cluster_master_count must be at least 1."
  }
}

variable "cluster_data_count" {
  description = "Number of data nodes in the cluster"
  type        = number
  default     = 3

  validation {
    condition     = var.cluster_data_count >= 1
    error_message = "cluster_data_count must be at least 1."
  }
}

variable "environment" {
  description = "Name of environment."
  type        = string
  default     = "development"
}

variable "extra_files" {
  description = "Additional files to create on an instance."
  type = list(object({
    content     = string
    path        = string
    permissions = string
  }))
  default = []
}

variable "extra_repos" {
  description = "Additional APT repositories to configure on an instance."
  type = map(
    object(
      {
        source   = string
        key      = string
        machine  = optional(string)
        authFrom = optional(string)
        priority = optional(number)
      }
    )
  )
  default = {}
}

variable "idle_timeout_data" {
  description = "The amount of time a client or target connection can be idle before the load balancer (that fronts data nodes) closes it."
  type        = number
  default     = 4000
}

variable "idle_timeout_master" {
  description = "The amount of time a client or target connection can be idle before the load balancer (that fronts master nodes) closes it."
  type        = number
  default     = 4000
}

variable "instance_type" {
  description = "Instance type to run the elasticsearch node"
  type        = string
  default     = "t3.medium"
}

variable "instance_type_master" {
  description = "Instance type to run the elasticsearch master node. If null, use var.instance_type."
  type        = string
  default     = null
}

variable "instance_type_data" {
  description = "Instance type to run the elasticsearch data node. If null, use var.instance_type."
  type        = string
  default     = null
}

variable "key_pair_name" {
  description = "SSH keypair name to be deployed in EC2 instances"
  type        = string
}

variable "max_instance_lifetime_days" {
  description = "The maximum amount of time, in _days_, that an instance can be in service, values must be either equal to 0 or between 7 and 365 days."
  type        = number
  default     = 0
}


variable "packages" {
  description = "List of packages to install when the instances bootstraps."
  type        = list(string)
  default     = []
}

variable "puppet_debug_logging" {
  description = "Enable debug logging if true."
  type        = bool
  default     = false
}

variable "puppet_environmentpath" {
  description = "A path for directory environments."
  type        = string
  default     = "{root_directory}/environments"
}


variable "puppet_hiera_config_path" {
  description = "Path to hiera configuration file."
  type        = string
  default     = "{root_directory}/environments/{environment}/hiera.yaml"
}

variable "puppet_manifest" {
  description = "Path to puppet manifest. By default ih-puppet will apply {root_directory}/environments/{environment}/manifests/site.pp."
  type        = string
  default     = null
}

variable "puppet_module_path" {
  description = "Path to common puppet modules."
  type        = string
  default     = "{root_directory}/environments/{environment}/modules:{root_directory}/modules"
}

variable "master_nodes_root_volume_size" {
  description = "Root volume size in master EC2 instance in Gigabytes"
  type        = number
  default     = null
}

variable "data_nodes_root_volume_size" {
  description = "Root volume size in data EC2 instance in Gigabytes"
  type        = number
  default     = 30
}

variable "secret_elastic_readers" {
  description = "List of role ARNs that will have permissions to read elastic superuser secret."
  default     = null
  type        = list(string)
}

variable "smtp_credentials_secret" {
  description = "AWS secret name with SMTP credentials. The secret must contain a JSON with user and password keys."
  type        = string
  default     = null
}

variable "snapshot_bucket_prefix" {
  description = "A string prefix to a bucket name for snapshots. Random by default."
  type        = string
  default     = null
}

variable "snapshot_force_destroy" {
  description = "Destroy S3 bucket with Elasticsearch snapshots even if non-empty"
  type        = bool
  default     = false
}

variable "ssh_cidr_block" {
  description = "CIDR range that is allowed to SSH into the elastic instances."
  type        = string
  default     = "0.0.0.0/0"
}

variable "monitoring_cidr_block" {
  description = "CIDR range that is allowed to monitor elastic instances."
  type        = string
  default     = null

  validation {
    condition = (
      var.monitoring_cidr_block == null ||
      !can(regex("^0\\.0\\.0\\.0/0$", var.monitoring_cidr_block))
    )
    error_message = "Monitoring CIDR block should not be 0.0.0.0/0. Specify a restricted CIDR range for security."
  }
}

variable "subnet_ids" {
  description = "List of subnet ids where the elasticsearch instances will be created"
  type        = list(string)
}

variable "ubuntu_codename" {
  description = "Ubuntu version to use for the elasticsearch node"
  type        = string
  default     = "jammy"
}

variable "zone_id" {
  description = "Domain name zone ID where the website will be available"
  type        = string
}

variable "sns_topic_alarm_arn" {
  description = "ARN of SNS topic for Cloudwatch alarms on base EC2 instance."
  type        = string
  default     = null
}
variable "extra_instance_profile_permissions" {
  description = "A JSON with a permissions policy document. The policy will be attached to the ASG instance profile."
  type        = string
  default     = null
}

variable "alarm_emails" {
  description = <<-EOT
    List of email addresses to receive CloudWatch alarm notifications for Elasticsearch cluster monitoring.
    Covers ALB health, Lambda function errors, and infrastructure issues.

    IMPORTANT: After deployment, AWS SNS will send confirmation emails to each address.
    You MUST click the confirmation link in each email to activate notifications.

    At least one email address is required for all environments (dev needs monitoring too!).
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.alarm_emails) > 0
    error_message = "At least one alarm email address is required. Development environments need monitoring too!"
  }
}

variable "alarm_topic_arns" {
  description = <<-EOT
    List of existing SNS topic ARNs to receive CloudWatch alarm notifications.
    Use this for advanced integrations with PagerDuty, Slack, OpsGenie, etc.
    These topics receive notifications alongside alarm_emails.
  EOT
  type        = list(string)
  default     = []
}

variable "alarm_unhealthy_host_threshold" {
  description = "Number of unhealthy hosts before triggering alarm. Set to 0 for immediate alerting, 1 to alert when 2+ hosts are unhealthy."
  type        = number
  default     = 1
}

variable "alarm_target_response_time_threshold" {
  description = "Target response time threshold in seconds. Defaults to 80% of idle_timeout if not specified."
  type        = number
  default     = null
}

variable "alarm_success_rate_threshold" {
  description = "Minimum success rate percentage (non-5xx responses). Defaults to 99.0%."
  type        = number
  default     = 99.0
}

variable "alarm_cpu_utilization_threshold" {
  description = "CPU utilization percentage threshold for alarms. Defaults to autoscaling target + 30%."
  type        = number
  default     = null
}

variable "alarm_evaluation_periods" {
  description = "Number of consecutive periods exceeding threshold before triggering alarm."
  type        = number
  default     = 2

  validation {
    condition     = var.alarm_evaluation_periods >= 1
    error_message = "Alarm evaluation periods must be at least 1."
  }
}

variable "alarm_success_rate_period" {
  description = "Time window in seconds for success rate calculation. Must be 60, 300, 900, or 3600."
  type        = number
  default     = 300

  validation {
    condition     = contains([60, 300, 900, 3600], var.alarm_success_rate_period)
    error_message = "Success rate period must be 60, 300, 900, or 3600 seconds."
  }
}

variable "enable_cloudwatch_logging" {
  description = "Enable CloudWatch logging for the Elasticsearch cluster"
  type        = bool
  default     = true
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention in days (minimum 365 days required for compliance)"
  type        = number
  default     = 365

  validation {
    condition     = var.cloudwatch_log_retention_days >= 365
    error_message = "CloudWatch log retention must be at least 365 days for compliance requirements"
  }

  validation {
    condition     = contains([365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention must be one of the AWS-supported values: 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, or 3653 days."
  }
}


variable "cloudwatch_kms_rotation_period_days" {
  description = "Number of days between automatic KMS key rotations for CloudWatch logs encryption"
  type        = number
  default     = 90

  validation {
    condition     = var.cloudwatch_kms_rotation_period_days >= 90 && var.cloudwatch_kms_rotation_period_days <= 2560
    error_message = "KMS key rotation period must be between 90 and 2560 days"
  }
}

