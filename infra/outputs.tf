output "image" {
  description = "Referência completa da imagem construída."
  value       = local.image_ref
}

output "container_name" {
  description = "Nome do container gerenciado pelo Terraform."
  value       = docker_container.pipeline.name
}

output "network_name" {
  description = "Rede Docker criada para o laboratório."
  value       = docker_network.lab.name
}

output "volume_name" {
  description = "Volume Docker associado à saída do pipeline."
  value       = docker_volume.output.name
}

output "rebuild_hint" {
  description = "Lembrete do ciclo dispose/recreate."
  value       = "terraform destroy && terraform apply reconstrói o ambiente sem depender de memória operacional."
}
