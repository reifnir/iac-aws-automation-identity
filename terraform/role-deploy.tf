# Deploy tier: assumable only from the protected deploy branch. AWS rejects
# the exchange from any other ref regardless of pipeline configuration.
data "aws_iam_policy_document" "deploy_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.gitlab.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "gitlab.com:aud"
      values   = [local.gitlab_url]
    }

    condition {
      test     = "StringEquals"
      variable = "gitlab.com:project_id"
      values   = local.trusted_project_ids
    }

    condition {
      test     = "StringEquals"
      variable = "gitlab.com:sub"
      values   = local.deploy_subs
    }
  }
}

resource "aws_iam_role" "deploy" {
  name                 = "ReifnirAutomationDeploy"
  description          = "Deploy role for GitLab CI, assumable only from the ${local.deploy_branch} branch of projects under ${local.gitlab_group_path} via OIDC."
  assume_role_policy   = data.aws_iam_policy_document.deploy_trust.json
  max_session_duration = local.max_session_duration

  lifecycle {
    precondition {
      condition     = length(local.trusted_projects) > 0
      error_message = "No projects found under GitLab group '${local.gitlab_group_path}'; refusing to render trust policies."
    }
  }
}

# Placeholder permission policy. Per the ADR rollout, replace with a
# least-privilege policy matching the automation's actual API usage once
# CloudTrail shows what the jobs really call.
resource "aws_iam_role_policy_attachment" "deploy" {
  role       = aws_iam_role.deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
