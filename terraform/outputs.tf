output "oidc_provider_arn" {
  description = "ARN of the gitlab.com IAM OIDC identity provider."
  value       = aws_iam_openid_connect_provider.gitlab.arn
}

output "readonly_role_arn" {
  description = "Role for plan/preview jobs; assumable from any ref in the project. Set this as ROLE_ARN in read-tier CI jobs."
  value       = aws_iam_role.readonly.arn
}

output "trusted_projects" {
  description = "Projects whose CI jobs the roles trust (path => immutable project ID). Review this in plan output when the group's contents change."
  value       = local.trusted_projects
}

output "deploy_role_arn" {
  description = "Role for deployment jobs; assumable only from the protected deploy branch. Set this as ROLE_ARN in deploy-tier CI jobs."
  value       = aws_iam_role.deploy.arn
}
