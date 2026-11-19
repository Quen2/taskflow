# =============================================================================
# main.tf : l'environnement staging de TaskFlow, traduction de compose.staging.yaml
# Mêmes noms d'objets Docker qu'à l'étape 2 : taskflow-staging(-db|-api|-front|-pgdata)
# =============================================================================

locals {
  prefix = "taskflow-${var.environment}"

  # Le mot de passe fourni (TF_VAR_db_password) s'il existe, sinon l'aléatoire.
  db_password  = coalesce(var.db_password, random_password.db.result)
  database_url = "postgres://taskflow:${local.db_password}@db:5432/taskflow"
}

# Mot de passe aléatoire, SANS caractères spéciaux : il finit dans une URL.
resource "random_password" "db" {
  length  = 32
  special = false
}

# ---------- Réseau et volume -------------------------------------------------

resource "docker_network" "this" {
  name = local.prefix
}

resource "docker_volume" "pgdata" {
  name = "${local.prefix}-pgdata"

  # Le volume existant a été créé par Compose, qui y a posé ses propres labels
  # (com.docker.compose.*). Sans cette ligne, OpenTofu voudrait le RECRÉER pour
  # retirer ces labels... et les données partiraient avec lui.
  lifecycle {
    ignore_changes = [labels]
  }
}

# ---------- Images ---------------------------------------------------------------

resource "docker_image" "postgres" {
  name         = "postgres:16-alpine"
  keep_locally = true
}

resource "docker_image" "api" {
  name         = "ghcr.io/${var.ghcr_owner}/taskflow-api:${var.image_tag}"
  keep_locally = true
}

resource "docker_image" "front" {
  name         = "ghcr.io/${var.ghcr_owner}/taskflow-front:${var.image_tag}"
  keep_locally = true
}

# ---------- Conteneurs -------------------------------------------------------

resource "docker_container" "db" {
  name    = "${local.prefix}-db"
  image   = docker_image.postgres.image_id
  restart = "unless-stopped"

  env = [
    "POSTGRES_USER=taskflow",
    "POSTGRES_PASSWORD=${local.db_password}",
    "POSTGRES_DB=taskflow",
  ]

  volumes {
    volume_name    = docker_volume.pgdata.name
    container_path = "/var/lib/postgresql/data"
  }

  networks_advanced {
    name    = docker_network.this.name
    aliases = ["db"]
  }

  healthcheck {
    test     = ["CMD-SHELL", "pg_isready -U taskflow -d taskflow"]
    interval = "5s"
    timeout  = "3s"
    retries  = 10
  }

  # Attendre que le conteneur soit "healthy" avant de passer à la suite.
  wait         = true
  wait_timeout = 120
}

resource "docker_container" "api" {
  name    = "${local.prefix}-api"
  image   = docker_image.api.image_id
  restart = "unless-stopped"

  env = [
    "PORT=3000",
    "DATABASE_URL=${local.database_url}",
    "APP_ENV=${var.environment}",
  ]

  # Alias "api" : c'est le nom qu'utilise front/nginx.conf (http://api:3000).
  networks_advanced {
    name    = docker_network.this.name
    aliases = ["api"]
  }

  healthcheck {
    test         = ["CMD", "wget", "-q", "-O", "/dev/null", "http://127.0.0.1:3000/health"]
    interval     = "10s"
    timeout      = "3s"
    start_period = "10s"
    retries      = 3
  }

  wait         = true
  wait_timeout = 120

  depends_on = [docker_container.db]
}

resource "docker_container" "front" {
  name    = "${local.prefix}-front"
  image   = docker_image.front.image_id
  restart = "unless-stopped"

  # Seul le front publie un port (pas de proxy en staging).
  ports {
    internal = 80
    external = var.front_port
  }

  networks_advanced {
    name = docker_network.this.name
  }

  healthcheck {
    test         = ["CMD", "wget", "-q", "--spider", "http://127.0.0.1/"]
    interval     = "5s"
    timeout      = "3s"
    start_period = "5s"
    retries      = 10
  }

  depends_on = [docker_container.api]
}
