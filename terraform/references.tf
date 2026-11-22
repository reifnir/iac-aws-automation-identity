data "aws_caller_identity" "current" {}

# AWS authentication for GitLab CI via OIDC web identity federation.
# See docs/identity-approach-adr.md for the full rationale.
data "gitlab_group" "trusted" {
  for_each  = local.gitlab_group_paths
  full_path = each.value
}

# Every project under each group, recursively through subgroups. Excludes
# archived projects (they cannot run pipelines) and projects merely shared
# into the group (with_shared would extend trust to foreign projects).
# If we ever have more than the max number of projects returnable, we'll need to re-evaluate the trust model; for now, 100 is plenty.
data "gitlab_projects" "trusted" {
  for_each          = data.gitlab_group.trusted
  group_id          = each.value.group_id
  include_subgroups = true
  with_shared       = false
  archived          = false
  per_page          = 100
}

data "tls_certificate" "gitlab" {
  url = local.gitlab_url
}

# Projections of references, so doesn't go into locals.tf
locals {
  # path_with_namespace => immutable numeric project ID
  # Flattened across all trusted groups.
  trusted_projects = merge([
    for g in data.gitlab_projects.trusted : {
      for p in g.projects : p.path_with_namespace => tostring(p.id)
    }
  ]...)

  gitlab_groups_description = join(", ", sort(local.gitlab_group_paths))

  # Groups that returned no projects; checked per group so a token that lost
  # access to one group can't silently drop that group's projects from trust.
  empty_trusted_groups = sort([for path, g in data.gitlab_projects.trusted : path if length(g.projects) == 0])

  # Sorted so trust policies are stable across runs regardless of API ordering.
  trusted_project_ids = sort(values(local.trusted_projects))
  readonly_subs       = sort([for path in keys(local.trusted_projects) : "project_path:${path}:*"])
  deploy_subs         = sort([for path in keys(local.trusted_projects) : "project_path:${path}:ref_type:branch:ref:${local.deploy_branch}"])
}

