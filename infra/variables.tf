variable "docker_host" {
  description = "Endpoint do daemon Docker. Deixe nulo para usar DOCKER_HOST ou o default do provider. Docker Desktop no macOS costuma usar unix:///Users/<usuario>/.docker/run/docker.sock."
  type        = string
  default     = null
  nullable    = true
}

variable "image_name" {
  description = "Nome da imagem do pipeline, sem a tag."
  type        = string
  default     = "ex2-dataops"
}

variable "image_tag" {
  description = "Tag imutável da imagem. Evite latest como identificador principal."
  type        = string
  default     = "v1"
}

variable "container_name" {
  description = "Nome do container criado pelo Terraform."
  type        = string
  default     = "ex2-dataops-pipeline"
}

variable "network_name" {
  description = "Nome da rede Docker do laboratório."
  type        = string
  default     = "ex2-dataops-net"
}

variable "volume_name" {
  description = "Nome do volume Docker usado para a saída."
  type        = string
  default     = "ex2-dataops-output"
}

variable "input_path" {
  description = "Caminho do CSV de entrada dentro do container."
  type        = string
  default     = "data/input/sample.csv"
}

variable "output_path" {
  description = "Caminho do CSV de saída dentro do container."
  type        = string
  default     = "data/output/orders_transformed.csv"
}

variable "environment" {
  description = "Nome lógico do ambiente de execução."
  type        = string
  default     = "lab"
}

variable "api_url" {
  description = "URL do serviço de notificação. Configuração, não segredo."
  type        = string
  default     = "http://localhost:8080"
}

variable "api_key" {
  description = "Segredo fictício injetado no container. Não versione o valor real."
  type        = string
  default     = ""
  sensitive   = true
}
