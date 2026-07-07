# AWS authentication from GitLab CI via OIDC federation

**Status:** Accepted
**Decision:** Authenticate GitLab CI jobs to AWS using OIDC web identity federation using SDK-native credential resolution via `AWS_WEB_IDENTITY_TOKEN_FILE`), replacing long-lived IAM user access keys.

## Background

Our automation runs from GitLab CI and needs to call AWS APIs. It does not run
from within AWS, so instance profiles and other AWS-native identity mechanisms
are unavailable to it. The historical answer to this shape of problem is an IAM
user with static access keys stored in CI variables. This document records why
we are not doing that, and what we are doing instead.

## Problems this solves

### Credential staleness and rotation burden

Static IAM access keys do not expire on their own. Keeping them fresh requires
a rotation process — scheduling, tooling, a grace-period scheme so in-flight
jobs on the old key don't fail mid-run, monitoring to catch a rotation that
silently stopped working, and a stored GitLab API token to update the CI
variables, which is itself a credential that needs lifecycle management. We
designed that system and it is workable, but it is machinery whose entire
purpose is to compensate for the existence of a long-lived secret.

With OIDC federation there is no long-lived secret to rotate. Every CI job
exchanges a per-job, GitLab-signed identity token for short-lived STS session
credentials. Effective rotation cadence goes from monthly to per-job, and the
rotation infrastructure goes from "a scheduled pipeline, a script, and a
project access token" to "nothing."

### Grace periods for in-flight jobs

A hard requirement was that rotating credentials must never invalidate the
credentials a currently-running job is using. Under the static-key design this
was achieved by exploiting the IAM two-active-keys limit, giving the outgoing
key one full cycle of overlap. Under OIDC the requirement is satisfied by
construction: each job holds its own independent STS session, and nothing any
other job or any administrative action in GitLab does can revoke it mid-run.
There is no shared credential for a rotation to break.

### Secret exposure surface

A masked CI variable is hidden from job logs, but it still exists: it can be
exfiltrated by a malicious dependency running inside a job, extracted by anyone
with maintainer access who runs a deliberately leaky pipeline, or captured from
runner infrastructure. Once exfiltrated, a static key works from anywhere on
the internet until someone notices and revokes it (unless those credentials are
constrained by SourceIp).

Under OIDC, no credential is stored in GitLab at all — not in variables, not
masked, not anywhere. This exceeds the original requirement ("even I don't need
access to the values"): there are no values. What a compromised job could steal
is a session token that expires within the hour and was issued against a role
whose permissions are scoped to that job's tier.

### Blast radius and privilege tiering

A single IAM user's keys carry the same permissions regardless of which branch
or pipeline uses them: a feature branch and a production deploy are
indistinguishable to AWS. The OIDC design gives us per-context roles enforced
by AWS itself. A read-only role is assumable from any ref in the project for
plan/preview work; the deploy role is assumable only from the protected `main`
branch, and AWS rejects the exchange from anywhere else no matter what the
pipeline configuration claims. Compromise of a feature branch cannot reach
deploy permissions.

### Constraint compliance

The solution honors the operating constraints established at the outset. There
is no persistent compute: STS is an API call, and nothing runs between jobs —
no EC2, no Lambda, no schedulers. Nothing depends on AWS CodePipeline or any
AWS-internal CI system; all automation remains in GitLab. And auditability
improves: every role session carries a session name derived from the project
and pipeline ID, so every AWS API call in CloudTrail traces back to the
specific pipeline that made it.

## The approach

### Trust establishment (one-time, Terraform)

An IAM OIDC identity provider is registered for `https://gitlab.com`. AWS will
accept identity tokens only if they are signed by GitLab's private keys
(verified against GitLab's published JWKS), carry the registered issuer, and
present the expected audience.

Two IAM roles are created, each with a trust policy that conditions on claims
GitLab's server asserts about the running job and that job authors cannot
forge or override:

`gitlab-ci-readonly` is assumable from any ref in our project
(`sub` matching `project_path:<our-project>:*`) and carries read-only
permissions for plan and preview jobs.

`gitlab-ci-deploy` is assumable only when the token's `sub` equals
`project_path:<our-project>:ref_type:branch:ref:main`, and carries the
deployment permissions.

Trust conditions pin the immutable numeric `project_id` claim in addition to
the project path. Paths on gitlab.com can be re-registered by a stranger if a
group is ever renamed or deleted; project IDs cannot, closing the namespace
reuse attack.

### Per-job credential acquisition

Each AWS-consuming job requests a GitLab `id_token` with the audience matching
the IAM provider registration. A shared base template writes the token to a
file and exports the standard web identity environment variables:

```yaml
.aws_oidc_base:
  id_tokens:
    GITLAB_OIDC_TOKEN:
      aud: https://gitlab.com
  before_script:
    - echo "${GITLAB_OIDC_TOKEN}" > "${CI_BUILDS_DIR}/.oidc_token"
    - export AWS_WEB_IDENTITY_TOKEN_FILE="${CI_BUILDS_DIR}/.oidc_token"
    - export AWS_ROLE_ARN="${ROLE_ARN}"
    - export AWS_ROLE_SESSION_NAME="gitlab-${CI_PROJECT_ID}-${CI_PIPELINE_ID}"
```

Jobs extend the template and set `ROLE_ARN` to the role for their tier. No
further authentication code is required in any job.

### Why this pattern specifically

This pattern delegates the token-for-credentials exchange to the AWS SDK
credential provider chain rather than calling `sts assume-role-with-web-identity`
explicitly. Every AWS SDK and every tool built on one — the AWS CLI, Terraform,
boto3-based scripts — resolves `AWS_WEB_IDENTITY_TOKEN_FILE` + `AWS_ROLE_ARN`
natively, so the same two environment variables authenticate all of our
tooling with zero per-tool configuration. The SDK also re-exchanges the token
and refreshes session credentials automatically, so long-running jobs do not
die at the one-hour session boundary the way a fixed-duration explicit
assume-role session would. The explicit pattern remains documented as a
fallback for any future tool that reads only the raw
`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_SESSION_TOKEN` variables and
does not speak web identity.

## Why this is safe on a shared GitLab instance

The audience value is not a secret and is not the boundary — any gitlab.com
user can put the same `aud` in their own pipeline. Security rests on the claim
conditions in each role's trust policy: the `sub`, `project_id`, and ref
claims are set by GitLab's servers according to where the job is actually
running and cannot be supplied or altered by a job author. A validly-signed
token from any other project carries that project's identity and fails our
conditions. The layered checks are: token signature against GitLab's keys
(excludes forgeries), issuer and audience match (excludes tokens minted for
other relying parties), claim conditions (excludes every project but ours),
and finally the role's own permission policy (bounds what a legitimate session
can do).

## Accepted trade-offs and residual risks

Credentials exist only inside CI jobs. Anything needing AWS access outside a
GitLab pipeline cannot use this mechanism; if such a consumer appears, the
previously designed key-rotation scheme can be bolted on for that single
credential without disturbing this design.

AWS must be able to reach the issuer's JWKS endpoint. Trivially true for
gitlab.com; a future migration to self-managed GitLab behind a firewall would
require exposing the OIDC discovery endpoints to AWS.

Session duration must cover job duration. The SDK's automatic refresh handles
this in the normal case, but the identity token's own lifetime is tied to the
job timeout, and roles have a `max_session_duration`. Unusually long jobs
should be checked against both.

Trust policy correctness is now the crown jewel. A wildcard typo in a `sub`
condition could widen trust dramatically (in the worst case, to all of
gitlab.com). Trust policies live in Terraform, change through review, and
should be treated with the same care as the credentials they replace.

## Rollout

Apply the Terraform using the existing hand-rolled bootstrap credentials.
Verify the read-only role with an `aws sts get-caller-identity` job from a
feature branch, and the deploy role from `main`. Migrate consuming jobs onto
the base template tier by tier. Once all jobs run on OIDC, delete the
bootstrap IAM user's access keys, leaving the account with no long-lived
credentials for this workflow. Follow up by replacing the placeholder role
permission policies with least-privilege policies matching the automation's
actual API usage.
