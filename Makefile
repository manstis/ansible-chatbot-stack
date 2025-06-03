# Makefile for Ansible Chatbot Stack

# Default values for environment variables
PYPI_VERSION ?= $(PYPI_VERSION)
ANSIBLE_CHATBOT_VERSION ?= aap-$(PYPI_VERSION)
ANSIBLE_CHATBOT_VLLM_URL ?= ${ANSIBLE_CHATBOT_VLLM_URL}
ANSIBLE_CHATBOT_VLLM_API_TOKEN ?= ${ANSIBLE_CHATBOT_VLLM_API_TOKEN}
ANSIBLE_CHATBOT_INFERENCE_MODEL ?= ${ANSIBLE_CHATBOT_INFERENCE_MODEL}
LLAMA_STACK_PORT ?= 8321

.PHONY: install-providers build build-custom run clean all deploy-k8s shell

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
	@echo ""
	@echo "Required Environment variables:"
	@echo "  PYPI_VERSION                  	- PyPI version of llama-stack (default: $(PYPI_VERSION))"
	@echo "  ANSIBLE_CHATBOT_VERSION       	- Version tag for the image (default: $(ANSIBLE_CHATBOT_VERSION))"
	@echo "  ANSIBLE_CHATBOT_VLLM_URL      	- URL for the vLLM inference provider"
	@echo "  ANSIBLE_CHATBOT_VLLM_API_TOKEN 	- API token for the vLLM inference provider"
	@echo "  ANSIBLE_CHATBOT_INFERENCE_MODEL	- Inference model to use"
	@echo "  LLAMA_STACK_PORT              	- Port to expose (default: $(LLAMA_STACK_PORT))"

check-prereqs:
	@echo "Checking prerequisites..."
	@command -v docker >/dev/null 2>&1 || command -v podman >/dev/null 2>&1 || { echo "Error: docker or podman is required but not installed." >&2; exit 1; }
	@echo "Prerequisites check passed."

setup: check-prereqs
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
		echo "Warning: aap_faiss_store.db not found in the repository root."; \
		echo "Please copy the aap_faiss_store.db file to the repository root before building."; \
	else \
		echo "aap_faiss_store.db found."; \
	fi

build: check-prereqs check-faiss-db
	@echo "Building base Ansible Chatbot Stack image..."
	export PYPI_VERSION=$(PYPI_VERSION) && \
	export LLAMA_STACK_LOGGING=server=debug;core=info && \
	export UV_HTTP_TIMEOUT=120 && \
	. venv/bin/activate && \
	llama stack build --config ansible-chatbot-build.yaml --image-type container
	@echo "Base image ansible-chatbot:$(PYPI_VERSION) built successfully."

build-custom: build
	@echo "Building customized Ansible Chatbot Stack image..."
	docker build -f Containerfile -t ansible-chatbot:$(ANSIBLE_CHATBOT_VERSION) --build-arg LLAMA_STACK_VERSION=$(PYPI_VERSION) .
	@echo "Custom image ansible-chatbot:$(ANSIBLE_CHATBOT_VERSION) built successfully."

run:
	@echo "Running Ansible Chatbot Stack container..."
	@echo "Using vLLM URL: $(ANSIBLE_CHATBOT_VLLM_URL)"
	@echo "Using inference model: $(ANSIBLE_CHATBOT_INFERENCE_MODEL)"
	docker run --security-opt label=disable -it -p $(LLAMA_STACK_PORT):$(LLAMA_STACK_PORT) \
	  --env LLAMA_STACK_PORT=$(LLAMA_STACK_PORT) \
	  --env VLLM_URL=$(ANSIBLE_CHATBOT_VLLM_URL) \
	  --env VLLM_API_TOKEN=$(ANSIBLE_CHATBOT_VLLM_API_TOKEN) \
	  --env INFERENCE_MODEL=$(ANSIBLE_CHATBOT_INFERENCE_MODEL) \
	  ansible-chatbot:$(ANSIBLE_CHATBOT_VERSION)

clean:
	@echo "Cleaning up..."
	rm -rf providers.d/
	docker rmi -f $$(docker images -a -q --filter reference=ansible-chatbot) || true
	@echo "Clean-up complete."

deploy-k8s:
	@echo "Deploying to Kubernetes cluster..."
	kubectl apply -f ansible-chatbot-deploy.yaml
	@echo "Deployment initiated. Verify using kubectl commands."

shell:
	@echo "Getting a shell in the container..."
	docker run --security-opt label=disable -it --entrypoint /bin/bash ansible-chatbot:$(ANSIBLE_CHATBOT_VERSION)

all: setup install-providers build build-custom
	@echo "All build steps completed successfully."
	@echo "To run the container, use: make run"
