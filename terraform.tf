terraform {
  required_version = "~> 1.5"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # website-pod 6.4.0 requires >= 6.33.0 for cpu_options.nested_virtualization.
      # Declaring the floor here fails init with a clear message instead of a
      # constraint conflict deep in the module tree.
      version = ">= 6.33.0, < 7.0.0"
      configuration_aliases = [
        aws.dns # AWS provider for DNS
      ]
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
