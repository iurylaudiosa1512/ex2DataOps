terraform {
  required_version = ">= 1.5.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {
  host = var.docker_host
}

locals {
  image_ref = "${var.image_name}:${var.image_tag}"
}

resource "docker_network" "lab" {
  name = var.network_name
}

resource "docker_volume" "output" {
  name = var.volume_name
}

resource "docker_image" "pipeline" {
  name = local.image_ref

  build {
    context    = abspath("${path.module}/..")
    dockerfile = "Dockerfile"
  }

  keep_locally = true
}

resource "docker_container" "pipeline" {
  name  = var.container_name
  image = docker_image.pipeline.image_id

  must_run = false
  restart  = "no"

  env = [
    "INPUT_PATH=${var.input_path}",
    "OUTPUT_PATH=${var.output_path}",
    "ENVIRONMENT=${var.environment}",
    "API_URL=${var.api_url}",
    "API_KEY=${var.api_key}",
  ]

  networks_advanced {
    name = docker_network.lab.name
  }

  volumes {
    host_path      = abspath("${path.module}/../data/input")
    container_path = "/app/data/input"
    read_only      = true
  }

  volumes {
    volume_name    = docker_volume.output.name
    container_path = "/app/data/output"
  }
}
