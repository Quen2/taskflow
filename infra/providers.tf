# Provider Docker : par défaut /var/run/docker.sock (le runner, et notre alias tofu).
# Authentification à ghcr.io seulement si un jeton est fourni (TF_VAR_ghcr_token) :
# dans le pipeline, c'est le GITHUB_TOKEN du run.
provider "docker" {
  dynamic "registry_auth" {
    for_each = var.ghcr_token == null ? [] : [1]
    content {
      address  = "ghcr.io"
      username = var.ghcr_username
      password = var.ghcr_token
    }
  }
}
