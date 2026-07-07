# The sub/project_id/aud condition keys below are asserted by GitLab's servers
# about the running job and cannot be forged or overridden by job authors.
# These conditions are the security boundary — treat changes to them with the
# same care as the credentials they replace. In particular, a wildcard typo in
# a sub condition could widen trust to all of gitlab.com.

# Read-only tier: assumable from any ref in the project, for plan/preview jobs.
data "aws_iam_policy_document" "readonly_trust" {
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

    # The numeric project IDs are immutable and survive group/project renames;
    # pinning them closes the gitlab.com namespace-reuse attack. Both claims
    # come from the same GitLab-signed token, so the two OR-sets cannot be
    # mixed and matched across projects.
    condition {
      test     = "StringEquals"
      variable = "gitlab.com:project_id"
      values   = local.trusted_project_ids
    }

    condition {
      test     = "StringLike"
      variable = "gitlab.com:sub"
      values   = local.readonly_subs
    }
  }
}

resource "aws_iam_role" "readonly" {
  name                 = "ReifnirAutomationReadOnly"
  description          = "Read-only role for GitLab CI plan/preview jobs, assumable from any ref of any project under ${local.gitlab_group_path} via OIDC."
  assume_role_policy   = data.aws_iam_policy_document.readonly_trust.json
  max_session_duration = local.max_session_duration

  lifecycle {
    # An empty project list would render a trust policy with no valid
    # principal conditions; fail loudly instead (likely a token/permission
    # problem on the GitLab lookup).
    precondition {
      condition     = length(local.trusted_projects) > 0
      error_message = "No projects found under GitLab group '${local.gitlab_group_path}'; refusing to render trust policies."
    }
  }
}

# ReadOnlyAccess is missing A LOT, so we'll need to add more permissions as AccessDenied events show up in CloudTrail.
resource "aws_iam_role_policy_attachment" "readonly" {
  role       = aws_iam_role.readonly.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
