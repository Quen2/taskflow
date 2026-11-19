# Valeurs affichées après un apply, lisibles avec : tofu output -raw <nom>
output "url" {
  description = "Adresse du staging"
  value       = "http://localhost:${var.front_port}"
}

output "health_url" {
  description = "Adresse du healthcheck (smoke test)"
  value       = "http://localhost:${var.front_port}/health"
}

output "image_tag" {
  description = "Version déployée"
  value       = var.image_tag
}

output "containers" {
  description = "Noms des conteneurs"
  value       = [docker_container.db.name, docker_container.api.name, docker_container.front.name]
}

output "network" {
  description = "Nom du réseau"
  value       = docker_network.this.name
}
