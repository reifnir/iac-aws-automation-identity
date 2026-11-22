variable "gitlab_token" {
  description = "GitLab personal access token used to enumerate projects under the trusted groups and to manage their group CI/CD variables. Needs api scope and Owner on every group in local.gitlab_group_paths. Set this as a CI/CD variable in the project."
  type        = string
  sensitive   = true
  ephemeral   = true
}
