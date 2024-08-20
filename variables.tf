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
  type = map(object({
    source = string
    key    = string
  }))
  default = {}
}

variable "instance_type" {
  description = "Instance type to run the elasticsearch node"
  type        = string
  default     = "t3.medium"
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

variable "puppet_hiera_config_path" {
  description = "Path to hiera configuration file."
  default     = "{root_directory}/environments/{environment}/hiera.yaml"
}

variable "puppet_module_path" {
  description = "Path to common puppet modules."
  default     = "{root_directory}/modules"
}

variable "puppet_root_directory" {
  description = "Path where the puppet code is hosted."
  default     = "/opt/puppet-code"
}

variable "root_volume_size" {
  description = "Root volume size in EC2 instance in Gigabytes"
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
