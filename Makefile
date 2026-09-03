PYTHON ?= python3
IMAGE ?= ex2-dataops
TAG ?= v1
COMPOSE ?= docker compose

# Docker Desktop (macOS) não usa /var/run/docker.sock. Reaproveita o endpoint do CLI.
DOCKER_HOST ?= $(shell docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null)
export DOCKER_HOST

ifneq (,$(wildcard .env))
  include .env
  export
endif

.PHONY: install test run docker-build docker-run compose-up compose-down infra-plan infra-up infra-down

install:
	$(PYTHON) -m pip install -r requirements-dev.txt

test:
	$(PYTHON) -m pytest

run:
	$(PYTHON) -m src.pipeline

docker-build:
	docker build -t $(IMAGE):$(TAG) .

docker-run:
	docker run --rm \
		--env-file .env \
		-v "$(PWD)/data:/app/data" \
		$(IMAGE):$(TAG)

compose-up:
	$(COMPOSE) up --build --abort-on-container-exit

compose-down:
	$(COMPOSE) down

infra-plan:
	cd infra && terraform init -input=false && terraform plan

infra-up:
	cd infra && terraform init -input=false && terraform apply -auto-approve

infra-down:
	cd infra && terraform destroy -auto-approve
