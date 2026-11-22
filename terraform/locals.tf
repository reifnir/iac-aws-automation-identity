locals {
  # If these things don't really vary, don't make them variables; just hardcode them here.
  # If they do vary, make them variables and pass them in from the CI/CD pipeline.
  deploy_branch        = "main"
  gitlab_url           = "https://gitlab.com"
  max_session_duration = 3600 # One hour
  region               = "us-east-1"

  # Every project under each of these groups (recursively through subgroups) is trusted.
  gitlab_group_paths = toset([
    "reifnir-private-projects",
    "reifnir-public-projects",
  ])
}
