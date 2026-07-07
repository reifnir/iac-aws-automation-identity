# AWS authentication for GitLab CI via OIDC web identity federation.
# See docs/identity-approach-adr.md for the full rationale.
data "gitlab_group" "trusted" {
  full_path = local.gitlab_group_path
}

# Every project under the group, recursively through subgroups. Excludes
# archived projects (they cannot run pipelines) and projects merely shared
# into the group (with_shared would extend trust to foreign projects).
# If we ever have more than the max number of projects returnable, we'll need to re-evaluate the trust model; for now, 100 is plenty.
data "gitlab_projects" "trusted" {
  group_id          = data.gitlab_group.trusted.group_id
  include_subgroups = true
  with_shared       = false
  archived          = false
  per_page          = 100
}

locals {
  # path_with_namespace => immutable numeric project ID
  trusted_projects = {
    for p in data.gitlab_projects.trusted.projects : p.path_with_namespace => tostring(p.id)
  }

  # Sorted so trust policies are stable across runs regardless of API ordering.
  trusted_project_ids = sort(values(local.trusted_projects))
  readonly_subs       = sort([for path in keys(local.trusted_projects) : "project_path:${path}:*"])
  deploy_subs         = sort([for path in keys(local.trusted_projects) : "project_path:${path}:ref_type:branch:ref:${local.deploy_branch}"])
}

data "tls_certificate" "gitlab" {
  url = local.gitlab_url
}
