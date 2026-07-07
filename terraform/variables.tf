variable "gitlab_token" {
  description = "GitLab personal access token with read_api scope, used to enumerate projects under the trusted group. Set this as a CI/CD variable in the project."
  type        = string
  sensitive   = true
  ephemeral   = true
}
