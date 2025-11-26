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
}

variable "cluster_master_count" {
  description = "Number of master nodes in the cluster"
  type        = number
  default     = 3
}

variable "cluster_data_count" {
  description = "Number of data nodes in the cluster"
  type        = number
  default     = 3
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

variable "internet_gateway_id" { # tflint-ignore: terraform_unused_declarations
  description = "Not used, but AWS Internet Gateway must be present. Ensure by passing its id."
  type        = string
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
  default     = "{root_directory}/environments/{environment}/hiera.yaml"
}

variable "puppet_manifest" {
  description = "Path to puppet manifest. By default ih-puppet will apply {root_directory}/environments/{environment}/manifests/site.pp."
  type        = string
  default     = null
}

variable "puppet_module_path" {
  description = "Path to common puppet modules."
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
    error_message = "CloudWatch log retention must be at least 365 days for compliance requirements. Current value: ${var.cloudwatch_log_retention_days} days."
  }

  validation {
    condition     = contains([365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.cloudwatch_log_retention_days)
    error_message = "CloudWatch log retention must be one of the AWS-supported values: 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, or 3653 days."
  }
}


variable "cloudwatch_log_rotation_period_days" {
  description = "KMS key automatic rotation period in days (90-2560)"
  type        = number
  default     = 90

  validation {
    condition     = var.cloudwatch_log_rotation_period_days >= 90 && var.cloudwatch_log_rotation_period_days <= 2560
    error_message = "KMS rotation period must be between 90 and 2560 days"
  }
}

