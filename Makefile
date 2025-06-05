# Makefile for Ansible Chatbot Stack

# Default values for environment variables
QUAY_ORG ?=
LLAMA_STACK_PYPI_VERSION ?=
ANSIBLE_CHATBOT_STACK_VERSION ?=
ANSIBLE_CHATBOT_VLLM_URL ?=
ANSIBLE_CHATBOT_VLLM_API_TOKEN ?=
ANSIBLE_CHATBOT_INFERENCE_MODEL ?=
LLAMA_STACK_PORT ?= 8321
LOCAL_DB_PATH ?= .
CONTAINER_DB_PATH ?= /.llama/data/distributions/ansible-chatbot

# Colors for terminal output
RED := \033[0;31m
NC := \033[0m # No Color

.PHONY: help install-providers build build-custom run clean all deploy-k8s shell tag-and-push

help:
	@echo "Makefile for Ansible Chatbot Stack"
	@echo "Available targets:"
	@echo "  help              - Show this help message"
	@echo "  all               - Run all steps (setup, install-providers, build, build-custom)"
	@echo "  install-providers - Install external providers"
	@echo "  build             - Build the base Ansible Chatbot Stack image"
	@echo "  build-custom      - Build the customized Ansible Chatbot Stack image"
	@echo "  run               - Run the Ansible Chatbot Stack container"
	@echo "  run-local-db      - Run the Ansible Chatbot Stack container with local DB mapped to conatiner DB"
	@echo "  clean             - Clean up generated files and Docker images"
	@echo "  deploy-k8s        - Deploy to Kubernetes cluster"
	@echo "  shell             - Get a shell in the container"
	@echo "  tag-and-push      - Tag and push the container image to quay.io"
	@echo ""
	@echo "Required Environment variables:"
	@echo "  ANSIBLE_CHATBOT_STACK_VERSION       	- Version tag for the image (default: $(ANSIBLE_CHATBOT_STACK_VERSION))"
	@echo "  ANSIBLE_CHATBOT_VLLM_URL      	- URL for the vLLM inference provider"
	@echo "  ANSIBLE_CHATBOT_VLLM_API_TOKEN 	- API token for the vLLM inference provider"
	@echo "  ANSIBLE_CHATBOT_INFERENCE_MODEL	- Inference model to use"
	@echo "  CONTAINER_DB_PATH           		- Path to the container database (default: $(CONTAINER_DB_PATH))"
	@echo "  LOCAL_DB_PATH               		- Path to the local database (default: $(LOCAL_DB_PATH))"
	@echo "  LLAMA_STACK_PYPI_VERSION       	- PyPI version of llama-stack (default: $(LLAMA_STACK_PYPI_VERSION))"
	@echo "  LLAMA_STACK_PORT              	- Port to expose (default: $(LLAMA_STACK_PORT))"
	@echo "  QUAY_ORG                		- Quay organization name (default: $(QUAY_ORG))"

setup:
	@echo "Setting up environment..."
	python3 -m venv venv
	. venv/bin/activate && pip install -r requirements.txt
	@echo "Environment setup complete."

install-providers:
	@echo "Installing external providers..."
	mkdir -p ~/.llama/providers.d/inline/safety ~/.llama/providers.d/remote/tool_runtime
	wget -q https://raw.githubusercontent.com/lightspeed-core/lightspeed-providers/refs/heads/main/resources/external_providers/inline/safety/lightspeed_question_validity.yaml \
	  -O ~/.llama/providers.d/inline/safety/lightspeed_question_validity.yaml
	wget -q https://raw.githubusercontent.com/lightspeed-core/lightspeed-providers/refs/heads/main/resources/external_providers/remote/tool_runtime/lightspeed.yaml \
	  -O ~/.llama/providers.d/remote/tool_runtime/lightspeed.yaml
	. venv/bin/activate && pip install lightspeed_stack_providers
	@echo "External providers installed."

build:
	@echo "Building base Ansible Chatbot Stack image..."
	export LLAMA_STACK_LOGGING=server=debug;core=info && \
	export UV_HTTP_TIMEOUT=120 && \
	. venv/bin/activate && \
	llama stack build --config ansible-chatbot-build.yaml --image-type container
	@echo "Base image $(RED)ansible-chatbot-stack-base$(NC) built successfully."

# Pre-check required environment variables for build-custom
check-env-build-custom:
	@if [ -z "$(ANSIBLE_CHATBOT_STACK_VERSION)" ]; then \
		echo "$(RED)Error: ANSIBLE_CHATBOT_STACK_VERSION is required but not set$(NC)"; \
		exit 1; \
	fi

build-custom: check-env-build-custom build
	@echo "Building customized Ansible Chatbot Stack image..."
	docker build -f Containerfile -t ansible-chatbot-stack:$(ANSIBLE_CHATBOT_STACK_VERSION) --build-arg ANSIBLE_CHATBOT_STACK_VERSION=$(ANSIBLE_CHATBOT_STACK_VERSION) .
	@echo "Custom image $(RED)ansible-chatbot-stack:$(ANSIBLE_CHATBOT_STACK_VERSION)$(NC) built successfully."

# Pre-check for required environment variables
check-env-run:
	@if [ -z "$(ANSIBLE_CHATBOT_VLLM_URL)" ]; then \
		echo "$(RED)Error: ANSIBLE_CHATBOT_VLLM_URL is required but not set$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$(ANSIBLE_CHATBOT_VLLM_API_TOKEN)" ]; then \
		echo "$(RED)Error: ANSIBLE_CHATBOT_VLLM_API_TOKEN is required but not set$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$(ANSIBLE_CHATBOT_INFERENCE_MODEL)" ]; then \
		echo "$(RED)Error: ANSIBLE_CHATBOT_INFERENCE_MODEL is required but not set$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$(ANSIBLE_CHATBOT_STACK_VERSION)" ]; then \
		echo "$(RED)Error: ANSIBLE_CHATBOT_STACK_VERSION is required but not set$(NC)"; \
		exit 1; \
	fi

run: check-env-run
	@echo "Running Ansible Chatbot Stack container..."
	@echo "Using vLLM URL: $(ANSIBLE_CHATBOT_VLLM_URL)"
	@echo "Using inference model: $(ANSIBLE_CHATBOT_INFERENCE_MODEL)"
	docker run --security-opt label=disable -it -p $(LLAMA_STACK_PORT):$(LLAMA_STACK_PORT) \
	  --env LLAMA_STACK_PORT=$(LLAMA_STACK_PORT) \
	  --env VLLM_URL=$(ANSIBLE_CHATBOT_VLLM_URL) \
	  --env VLLM_API_TOKEN=$(ANSIBLE_CHATBOT_VLLM_API_TOKEN) \
	  --env INFERENCE_MODEL=$(ANSIBLE_CHATBOT_INFERENCE_MODEL) \
	  ansible-chatbot-stack:$(ANSIBLE_CHATBOT_STACK_VERSION)

# Pre-check required environment variables for local DB run
check-env-run-local-db: check-env-run
	@if [ -z "$(LOCAL_DB_PATH)" ]; then \
		echo "$(RED)Error: LOCAL_DB_PATH is required but not set$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$(CONTAINER_DB_PATH)" ]; then \
		echo "$(RED)Error: CONTAINER_DB_PATH is required but not set$(NC)"; \
		exit 1; \
	fi

run-local-db: check-env-run-local-db
	@echo "Running Ansible Chatbot Stack container..."
	@echo "Using vLLM URL: $(ANSIBLE_CHATBOT_VLLM_URL)"
	@echo "Using inference model: $(ANSIBLE_CHATBOT_INFERENCE_MODEL)"
	@echo "Mapping local DB from $(LOCAL_DB_PATH) to $(CONTAINER_DB_PATH)"
	docker run --security-opt label=disable -it -p $(LLAMA_STACK_PORT):$(LLAMA_STACK_PORT) \
	  -v $(LOCAL_DB_PATH):$(CONTAINER_DB_PATH) \
	  --env LLAMA_STACK_PORT=$(LLAMA_STACK_PORT) \
	  --env ANSIBLE_CHATBOT_VLLM_URL=$(ANSIBLE_CHATBOT_VLLM_URL) \
	  --env ANSIBLE_CHATBOT_VLLM_API_TOKEN=$(ANSIBLE_CHATBOT_VLLM_API_TOKEN) \
	  --env INFERENCE_MODEL=$(ANSIBLE_CHATBOT_INFERENCE_MODEL) \
	  ansible-chatbot-stack:$(ANSIBLE_CHATBOT_STACK_VERSION)

clean:
	@echo "Cleaning up..."
	rm -rf providers.d/
	@echo "Removing ansible-chatbot-stack images..."
	docker rmi -f $$(docker images -a -q --filter reference=ansible-chatbot-stack) || true
	@echo "Removing ansible-chatbot-stack-base image..."
	docker rmi -f $$(docker images -a -q --filter reference=ansible-chatbot-stack-base) || true
	@echo "Clean-up complete."

deploy-k8s:
	@echo Change configuration in `kustomization.yaml` accordingly, then deploy
	kubectl kustomize . > local-chatbot-stack-deploy.yaml
	@echo Deploy the service:
	kubectl apply -f local-chatbot-stack-deploy.yaml
	@echo "Deployment initiated. Verify using kubectl commands."

shell:
	@echo "Getting a shell in the container..."
	docker run --security-opt label=disable -it --entrypoint /bin/bash ansible-chatbot-stack:$(ANSIBLE_CHATBOT_VERSION)

# Pre-check required environment variables for tag-and-push
check-env-tag-and-push:
	@if [ -z "$(QUAY_ORG)" ]; then \
		echo "$(RED)Error: QUAY_ORG is required but not set$(NC)"; \
		exit 1; \
	fi
	@if [ -z "$(ANSIBLE_CHATBOT_STACK_VERSION)" ]; then \
		echo "$(RED)Error: ANSIBLE_CHATBOT_STACK_VERSION is required but not set$(NC)"; \
		exit 1; \
	fi

tag-and-push: check-env-tag-and-push
	@echo "Logging in to quay.io..."
	@echo "Please enter your quay.io credentials when prompted"
	docker login quay.io
	@echo "Tagging image ansible-chatbot-stack:$(ANSIBLE_CHATBOT_STACK_VERSION)"
	docker tag ansible-chatbot-stack:$(ANSIBLE_CHATBOT_STACK_VERSION) quay.io/$(QUAY_ORG)/ansible-chatbot-stack:$(ANSIBLE_CHATBOT_STACK_VERSION)
	@echo "Pushing image to quay.io..."
	docker push quay.io/$(QUAY_ORG)/ansible-chatbot-stack:$(ANSIBLE_CHATBOT_STACK_VERSION)
	@echo "Image successfully pushed to quay.io/$(QUAY_ORG)/ansible-chatbot-stack:$(ANSIBLE_CHATBOT_STACK_VERSION)"

all: setup install-providers build build-custom
	@echo "All build steps completed successfully."
	@echo "To run the container, use: $(RED)make run$(NC)"
	@echo "To tag and push the container to quay.io, use: $(RED)make tag-and-push$(NC)"
