# Versions exigées d'OpenTofu et des providers, et emplacement du state.
terraform {
  required_version = ">= 1.6"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.6"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Backend "local" VIDE : le chemin du state est donné à l'init
  # (tofu init -backend-config="path=..."), car il diffère entre le poste
  # et le runner. Et le state ne doit jamais être dans le dépôt.
  backend "local" {}
}
