variable "gitlab_token" {
  description = "GitLab personal access token used to enumerate projects under the trusted group and to manage its group CI/CD variables. Needs api scope and Owner on the group. Set this as a CI/CD variable in the project."
  type        = string
  sensitive   = true
  ephemeral   = true
}
