terraform {
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws    = { source = "hashicorp/aws" }
    tls    = { source = "hashicorp/tls" }
    gitlab = { source = "gitlabhq/gitlab" }
  }

  required_version = ">= 1.11.0"
}
