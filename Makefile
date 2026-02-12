# =============================================================================
# Makefile — Job Market Intelligence Platform
# =============================================================================
# Quick reference:
#   make install     — Install all dependencies
#   make dev         — Start everything (infra + services)
#   make test        — Run all tests
#   make lint        — Lint all services
#   make health      — Health check everything
#   make stop        — Stop everything
#   make help        — Show all available commands
# =============================================================================

.DEFAULT_GOAL := help
SHELL := /bin/bash

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPTS_DIR    := scripts
DOCKER_DIR     := docker
COMPOSE_FILE   := $(DOCKER_DIR)/docker-compose.yml
ENV_FILE       := $(DOCKER_DIR)/.env

# Colors
CYAN   := \033[0;36m
GREEN  := \033[0;32m
YELLOW := \033[1;33m
RED    := \033[0;31m
BOLD   := \033[1m
NC     := \033[0m

# ---------------------------------------------------------------------------
# Setup & Installation
# ---------------------------------------------------------------------------

.PHONY: install
install: ## Install all dependencies (clones repos + installs packages)
	@chmod +x $(SCRIPTS_DIR)/*.sh
	@$(SCRIPTS_DIR)/install.sh

.PHONY: install-skip-clone
install-skip-clone: ## Install dependencies without cloning (repos already exist)
	@chmod +x $(SCRIPTS_DIR)/*.sh
	@$(SCRIPTS_DIR)/install.sh --skip-clone

.PHONY: setup-env
setup-env: ## Create .env from .env.example (if not exists)
	@if [ ! -f $(ENV_FILE) ] && [ -f $(DOCKER_DIR)/.env.example ]; then \
		cp $(DOCKER_DIR)/.env.example $(ENV_FILE); \
		echo -e "$(GREEN)Created $(ENV_FILE) from .env.example$(NC)"; \
		echo -e "$(YELLOW)⚠ Update $(ENV_FILE) with your actual values$(NC)"; \
	else \
		echo -e "$(CYAN)$(ENV_FILE) already exists$(NC)"; \
	fi

# ---------------------------------------------------------------------------
# Development
# ---------------------------------------------------------------------------

.PHONY: dev
dev: ## Start infrastructure + all services in dev mode
	@chmod +x $(SCRIPTS_DIR)/dev.sh
	@$(SCRIPTS_DIR)/dev.sh

.PHONY: dev-infra
dev-infra: ## Start Docker infrastructure only (Kafka, Redis, ES, etc.)
	@chmod +x $(SCRIPTS_DIR)/dev.sh
	@$(SCRIPTS_DIR)/dev.sh --infra-only

.PHONY: dev-services
dev-services: ## Start application services only (infra must be running)
	@chmod +x $(SCRIPTS_DIR)/dev.sh
	@$(SCRIPTS_DIR)/dev.sh --services-only

.PHONY: stop
stop: ## Stop all services and infrastructure
	@chmod +x $(SCRIPTS_DIR)/dev.sh
	@$(SCRIPTS_DIR)/dev.sh --stop

# ---------------------------------------------------------------------------
# Docker Infrastructure
# ---------------------------------------------------------------------------

.PHONY: up
up: ## Start Docker containers (alias for docker compose up)
	@docker compose -f $(COMPOSE_FILE) up -d

.PHONY: down
down: ## Stop Docker containers
	@docker compose -f $(COMPOSE_FILE) down

.PHONY: restart
restart: down up ## Restart Docker containers

.PHONY: logs
logs: ## Tail Docker container logs (all services)
	@docker compose -f $(COMPOSE_FILE) logs -f

.PHONY: ps
ps: ## Show Docker container status
	@docker compose -f $(COMPOSE_FILE) ps

.PHONY: clean
clean: ## Stop containers and remove volumes (⚠ destroys data)
	@echo -e "$(RED)⚠ This will destroy all container data!$(NC)"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	@docker compose -f $(COMPOSE_FILE) down -v --remove-orphans

# ---------------------------------------------------------------------------
# Testing
# ---------------------------------------------------------------------------

.PHONY: test
test: ## Run all tests across all services
	@chmod +x $(SCRIPTS_DIR)/test.sh
	@$(SCRIPTS_DIR)/test.sh

.PHONY: test-coverage
test-coverage: ## Run tests with coverage reports
	@chmod +x $(SCRIPTS_DIR)/test.sh
	@$(SCRIPTS_DIR)/test.sh --coverage

.PHONY: test-watch
test-watch: ## Run tests in watch mode
	@chmod +x $(SCRIPTS_DIR)/test.sh
	@$(SCRIPTS_DIR)/test.sh --watch

.PHONY: test-unit
test-unit: ## Run unit tests only
	@chmod +x $(SCRIPTS_DIR)/test.sh
	@$(SCRIPTS_DIR)/test.sh --unit

.PHONY: test-integration
test-integration: ## Run integration tests only
	@chmod +x $(SCRIPTS_DIR)/test.sh
	@$(SCRIPTS_DIR)/test.sh --integration

# ---------------------------------------------------------------------------
# Linting & Formatting
# ---------------------------------------------------------------------------

.PHONY: lint
lint: ## Lint all services (check mode)
	@chmod +x $(SCRIPTS_DIR)/lint.sh
	@$(SCRIPTS_DIR)/lint.sh

.PHONY: lint-fix
lint-fix: ## Lint all services and auto-fix issues
	@chmod +x $(SCRIPTS_DIR)/lint.sh
	@$(SCRIPTS_DIR)/lint.sh --fix

# ---------------------------------------------------------------------------
# Health & Monitoring
# ---------------------------------------------------------------------------

.PHONY: health
health: ## Run health checks on all services
	@chmod +x $(SCRIPTS_DIR)/health-check.sh
	@$(SCRIPTS_DIR)/health-check.sh

.PHONY: health-infra
health-infra: ## Health check infrastructure only
	@chmod +x $(SCRIPTS_DIR)/health-check.sh
	@$(SCRIPTS_DIR)/health-check.sh --infra

.PHONY: health-services
health-services: ## Health check application services only
	@chmod +x $(SCRIPTS_DIR)/health-check.sh
	@$(SCRIPTS_DIR)/health-check.sh --services

.PHONY: health-json
health-json: ## Health check with JSON output
	@chmod +x $(SCRIPTS_DIR)/health-check.sh
	@$(SCRIPTS_DIR)/health-check.sh --json

.PHONY: health-wait
health-wait: ## Wait until all services are healthy
	@chmod +x $(SCRIPTS_DIR)/health-check.sh
	@$(SCRIPTS_DIR)/health-check.sh --wait

# ---------------------------------------------------------------------------
# Individual Services
# ---------------------------------------------------------------------------

.PHONY: dev-scraper
dev-scraper: ## Start scraper-service in dev mode
	@$(SCRIPTS_DIR)/dev.sh --service scraper-service

.PHONY: dev-nlp
dev-nlp: ## Start nlp-service in dev mode
	@$(SCRIPTS_DIR)/dev.sh --service nlp-service

.PHONY: dev-aggregation
dev-aggregation: ## Start aggregation-service in dev mode
	@$(SCRIPTS_DIR)/dev.sh --service aggregation-service

.PHONY: dev-auth
dev-auth: ## Start auth-service in dev mode
	@$(SCRIPTS_DIR)/dev.sh --service auth-service

.PHONY: dev-gateway
dev-gateway: ## Start api-gateway in dev mode
	@$(SCRIPTS_DIR)/dev.sh --service api-gateway

.PHONY: dev-frontend
dev-frontend: ## Start frontend in dev mode
	@$(SCRIPTS_DIR)/dev.sh --service frontend

.PHONY: test-scraper
test-scraper: ## Test scraper-service
	@$(SCRIPTS_DIR)/test.sh --service scraper-service

.PHONY: test-nlp
test-nlp: ## Test nlp-service
	@$(SCRIPTS_DIR)/test.sh --service nlp-service

.PHONY: test-aggregation
test-aggregation: ## Test aggregation-service
	@$(SCRIPTS_DIR)/test.sh --service aggregation-service

.PHONY: test-auth
test-auth: ## Test auth-service
	@$(SCRIPTS_DIR)/test.sh --service auth-service

.PHONY: test-gateway
test-gateway: ## Test api-gateway
	@$(SCRIPTS_DIR)/test.sh --service api-gateway

.PHONY: test-frontend
test-frontend: ## Test frontend
	@$(SCRIPTS_DIR)/test.sh --service frontend

.PHONY: test-shared
test-shared: ## Test shared types
	@$(SCRIPTS_DIR)/test.sh --service shared

.PHONY: lint-scraper
lint-scraper: ## Lint scraper-service
	@$(SCRIPTS_DIR)/lint.sh --service scraper-service

.PHONY: lint-nlp
lint-nlp: ## Lint nlp-service
	@$(SCRIPTS_DIR)/lint.sh --service nlp-service

.PHONY: lint-auth
lint-auth: ## Lint auth-service
	@$(SCRIPTS_DIR)/lint.sh --service auth-service

.PHONY: lint-gateway
lint-gateway: ## Lint api-gateway
	@$(SCRIPTS_DIR)/lint.sh --service api-gateway

.PHONY: lint-frontend
lint-frontend: ## Lint frontend
	@$(SCRIPTS_DIR)/lint.sh --service frontend

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

.PHONY: status
status: ps health ## Show full system status (containers + health)

.PHONY: reset
reset: clean install ## Full reset: destroy data, reinstall everything

.PHONY: deps-update
deps-update: ## Update dependencies across all services
	@echo -e "$(CYAN)Updating Bun dependencies...$(NC)"
	@for dir in ../shared ../scraper-service ../api-gateway ../frontend; do \
		if [ -f "$$dir/package.json" ]; then \
			echo "  Updating $$(basename $$dir)..."; \
			(cd "$$dir" && bun update 2>/dev/null) || true; \
		fi; \
	done
	@echo -e "$(CYAN)Updating Python dependencies...$(NC)"
	@if [ -d "../nlp-service/.venv" ]; then \
		(cd ../nlp-service && .venv/bin/pip install --upgrade -r requirements.txt 2>/dev/null) || true; \
	fi
	@echo -e "$(CYAN)Updating Go dependencies...$(NC)"
	@for dir in ../aggregation-service ../auth-service; do \
		if [ -f "$$dir/go.mod" ]; then \
			echo "  Updating $$(basename $$dir)..."; \
			(cd "$$dir" && go get -u ./... && go mod tidy 2>/dev/null) || true; \
		fi; \
	done
	@echo -e "$(GREEN)Dependencies updated$(NC)"

# ---------------------------------------------------------------------------
# Quick Access
# ---------------------------------------------------------------------------

.PHONY: kafka-ui
kafka-ui: ## Open Kafka UI in browser (if running)
	@echo "Kafka is available at localhost:9092"
	@echo "Use a Kafka UI tool like kafdrop or kowl for visual management"

.PHONY: kibana
kibana: ## Open Kibana in browser
	@echo "Kibana: http://localhost:5601"

.PHONY: es
es: ## Quick Elasticsearch cluster health check
	@curl -s http://localhost:9200/_cluster/health?pretty 2>/dev/null || echo "Elasticsearch not reachable"

.PHONY: redis-cli
redis-cli: ## Open Redis CLI
	@docker exec -it $$(docker compose -f $(COMPOSE_FILE) ps -q redis 2>/dev/null) redis-cli 2>/dev/null || echo "Redis container not running"

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

.PHONY: help
help: ## Show this help message
	@echo ""
	@echo -e "$(BOLD)$(CYAN)╔═══════════════════════════════════════════════════════════╗$(NC)"
	@echo -e "$(BOLD)$(CYAN)║   Job Market Intelligence — Available Commands            ║$(NC)"
	@echo -e "$(BOLD)$(CYAN)╚═══════════════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"} \
		/^[a-zA-Z_-]+:.*##/ { \
			printf "  $(CYAN)%-22s$(NC) %s\n", $$1, $$2 \
		} \
		/^# ---/ { \
			gsub(/^# -+/, ""); \
			gsub(/-+$$/, ""); \
			gsub(/^ +| +$$/, ""); \
			if (length($$0) > 0) printf "\n$(BOLD)%s$(NC)\n", $$0 \
		}' $(MAKEFILE_LIST)
	@echo ""
	@echo -e "$(BOLD)Quick Start:$(NC)"
	@echo -e "  $(CYAN)make install$(NC)     Clone repos and install dependencies"
	@echo -e "  $(CYAN)make dev$(NC)         Start everything"
	@echo -e "  $(CYAN)make health$(NC)      Verify all services running"
	@echo -e "  $(CYAN)make test$(NC)        Run all tests"
	@echo -e "  $(CYAN)make stop$(NC)        Stop everything"
	@echo ""