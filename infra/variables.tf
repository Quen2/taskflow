# Entrées du module. Les valeurs viennent de TF_VAR_<nom> (poste, ci-env.sh)
# ou d'un fichier terraform.tfvars (jamais commité).

variable "ghcr_owner" {
  description = "Propriétaire des images sur ghcr.io, en minuscules"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.ghcr_owner))
    error_message = "ghcr_owner : minuscules, chiffres et tirets uniquement (ghcr.io refuse les majuscules)."
  }
}

variable "image_tag" {
  description = "Version déployée : SHA court du commit, ou latest"
  type        = string
  default     = "latest"

  validation {
    condition     = can(regex("^([0-9a-f]{7}|latest)$", var.image_tag))
    error_message = "image_tag : SHA court (7 caractères hexadécimaux en minuscules) ou \"latest\"."
  }
}

variable "front_port" {
  description = "Port publié par le front sur le poste"
  type        = number
  default     = 8081

  validation {
    condition     = var.front_port >= 1024 && var.front_port <= 65535
    error_message = "front_port doit être compris entre 1024 et 65535."
  }
}

variable "environment" {
  description = "Nom de l'environnement (préfixe des ressources, APP_ENV)"
  type        = string
  default     = "staging"
}

variable "db_password" {
  description = "Mot de passe de la base. null = mot de passe aléatoire généré par OpenTofu"
  type        = string
  default     = null
  sensitive   = true
}

variable "ghcr_username" {
  description = "Utilisateur pour tirer les images privées de ghcr.io (null = pas d'authentification)"
  type        = string
  default     = null
}

variable "ghcr_token" {
  description = "Jeton pour tirer les images privées de ghcr.io"
  type        = string
  default     = null
  sensitive   = true
}
