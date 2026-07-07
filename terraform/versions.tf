provider "aws" {
  region = local.region
}

provider "gitlab" {
  token = var.gitlab_token
}
