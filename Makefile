# Makefile for Ansible Chatbot Stack

# Default values for environment variables
QUAY_ORG ?= $(QUAY_ORG)
LLAMA_STACK_PYPI_VERSION ?= $(LLAMA_STACK_PYPI_VERSION)
ANSIBLE_CHATBOT_STACK_VERSION ?= $(ANSIBLE_CHATBOT_STACK_VERSION)
ANSIBLE_CHATBOT_VLLM_URL ?= $(ANSIBLE_CHATBOT_VLLM_URL)
ANSIBLE_CHATBOT_VLLM_API_TOKEN ?= $(ANSIBLE_CHATBOT_VLLM_API_TOKEN)
ANSIBLE_CHATBOT_INFERENCE_MODEL ?= $(ANSIBLE_CHATBOT_INFERENCE_MODEL)
LLAMA_STACK_PORT ?= 8321

# Colors for terminal output
RED := \033[0;31m
NC := \033[0m # No Color

.PHONY: install-providers build build-custom run clean all deploy-k8s shell tag-and-push

help:
	@echo "Makefile for Ansible Chatbot Stack"
	@echo "Available targets:"
	@echo "  all               - Run all steps (setup, install-providers, build, build-custom)"
	@echo "  install-providers - Install external providers"
	@echo "  build             - Build the base Ansible Chatbot Stack image"
	@echo "  build-custom      - Build the customized Ansible Chatbot Stack image"
	@echo "  run               - Run the Ansible Chatbot Stack container"
	@echo "  clean             - Clean up generated files and Docker images"
	@echo "  deploy-k8s        - Deploy to Kubernetes cluster"
	@echo "  shell             - Get a shell in the container"
	@echo "  tag-and-push      - Tag and push the container image to quay.io"
	@echo ""
	@echo "Required Environment variables:"
	@echo "  LLAMA_STACK_PYPI_VERSION       	- PyPI version of llama-stack (default: $(LLAMA_STACK_PYPI_VERSION))"
	@echo "  ANSIBLE_CHATBOT_STACK_VERSION       	- Version tag for the image (default: $(ANSIBLE_CHATBOT_STACK_VERSION))"
	@echo "  ANSIBLE_CHATBOT_VLLM_URL      	- URL for the vLLM inference provider"
	@echo "  ANSIBLE_CHATBOT_VLLM_API_TOKEN 	- API token for the vLLM inference provider"
	@echo "  ANSIBLE_CHATBOT_INFERENCE_MODEL	- Inference model to use"
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

check-faiss-db:
	@if [ ! -f aap_faiss_store.db ]; then \
		echo "$(RED)Warning: aap_faiss_store.db not found in the repository root."; \
		echo "Please copy the aap_faiss_store.db file to the repository root before building.$(NC)"; \
	else \
		echo "aap_faiss_store.db found."; \
	fi

build: check-faiss-db
	@echo "Building base Ansible Chatbot Stack image..."
	export LLAMA_STACK_LOGGING=server=debug;core=info && \
	export UV_HTTP_TIMEOUT=120 && \
	. venv/bin/activate && \
	llama stack build --config ansible-chatbot-build.yaml --image-type container
	@echo "Base image $(RED)ansible-chatbot-stack-base$(NC) built successfully."

build-custom: build
	@echo "Building customized Ansible Chatbot Stack image..."
	docker build -f Containerfile -t ansible-chatbot-stack:$(ANSIBLE_CHATBOT_STACK_VERSION) --build-arg ANSIBLE_CHATBOT_STACK_VERSION=$(ANSIBLE_CHATBOT_STACK_VERSION) .
	@echo "Custom image $(RED)ansible-chatbot-stack:$(ANSIBLE_CHATBOT_STACK_VERSION)$(NC) built successfully."

run:
	@echo "Running Ansible Chatbot Stack container..."
	@echo "Using vLLM URL: $(ANSIBLE_CHATBOT_VLLM_URL)"
	@echo "Using inference model: $(ANSIBLE_CHATBOT_INFERENCE_MODEL)"
	docker run --security-opt label=disable -it -p $(LLAMA_STACK_PORT):$(LLAMA_STACK_PORT) \
	  --env LLAMA_STACK_PORT=$(LLAMA_STACK_PORT) \
	  --env VLLM_URL=$(ANSIBLE_CHATBOT_VLLM_URL) \
	  --env VLLM_API_TOKEN=$(ANSIBLE_CHATBOT_VLLM_API_TOKEN) \
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

tag-and-push:
	@echo "Logging in to quay.io..."
	@echo "Please enter your quay.io credentials when prompted"
	docker login quay.io
	@echo "Tagging image ansible-chatbot-stack:$(ANSIBLE_CHATBOT_STACK_VERSION)"
	docker tag ansible-chatbot-stack:$(ANSIBLE_CHATBOT_STACK_VERSION) quay.io/$(QUAY_ORG)/ansible-chatbot-stack:$(ANSIBLE_CHATBOT_STACK_VERSION)
	@echo "Pushing image to quay.io..."
	docker push quay.io/$(QUAY_ORG)/ansible-chatbot-stack:$(ANSIBLE_CHATBOT_STACK_VERSION)
	@echo "Image successfully pushed to quay.io/$(QUAY_ORG)/ansible-chatbot-stack:$(ANSIBLE_CHATBOT_STACK_VERSION)"

all: check-faiss-db setup install-providers build build-custom
	@echo "All build steps completed successfully."
	@echo "To run the container, use: $(RED)make run$(NC)"
	@echo "To tag and push the container to quay.io, use: $(RED)make tag-and-push$(NC)"
