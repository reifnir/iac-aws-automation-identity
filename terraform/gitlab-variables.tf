# Published at the group level so CI jobs in any trusted project can compose
# role ARNs without hardcoding the account ID.
resource "gitlab_group_variable" "aws_account_id_root" {
  group       = data.gitlab_group.trusted.id
  key         = "AWS_ACCOUNT_ID_ROOT"
  value       = data.aws_caller_identity.current.account_id
  description = "AWS account ID that holds the GitLab CI OIDC roles; maintained by the aws-automation-identity project."
  protected   = false # readonly-tier jobs run from unprotected refs and need it
  masked      = false # not a secret. the only people who need it are already trusted to assume the roles, and it's in the trust policy anyway.
}
