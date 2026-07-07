locals {
  # If these things don't really vary, don't make them variables; just hardcode them here.
  # If they do vary, make them variables and pass them in from the CI/CD pipeline.
  deploy_branch        = "main"
  gitlab_group_path    = "reifnir-public-projects"
  gitlab_url           = "https://gitlab.com"
  max_session_duration = 3600 # One hour
  region               = "us-east-1"
}
