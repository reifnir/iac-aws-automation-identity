# Trust establishment: AWS accepts identity tokens only if signed by GitLab
# (verified against GitLab's published JWKS), carrying this issuer, and
# presenting the registered audience.
resource "aws_iam_openid_connect_provider" "gitlab" {
  url            = local.gitlab_url
  client_id_list = [local.gitlab_url]

  # Root CA thumbprint. AWS validates gitlab.com against its own trusted CA
  # library and ignores this for most issuers, but the API requires a value.
  thumbprint_list = [data.tls_certificate.gitlab.certificates[0].sha1_fingerprint]
}
