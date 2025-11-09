# Docker Compose utility
COMPOSE ?= docker compose

# Docker Compose project name
PROJECT_NAME ?= moodle-ai

# Plugin name (used for archiving)
PLUGIN_NAME ?= moodle-ru-ai-plugin

# List of plugin directories for ZIP packaging
PLUGINS_DIRS := ai_manager moodle-block_ai_chat moodle-block_ai_control moodle-qbank_questiongen moodle-qtype_aitext moodle-tiny_ai

# Build artifacts directory
DIST_DIR ?= dist

# Paths inside Moodle container
MOODLE_ROOT := /bitnami/moodle/public
LOCAL_DIR := $(MOODLE_ROOT)/local
BLOCKS_DIR := $(MOODLE_ROOT)/blocks
QUESTION_BANK_DIR := $(MOODLE_ROOT)/question/bank
QUESTION_TYPE_DIR := $(MOODLE_ROOT)/question/type
TINY_PLUGINS_DIR := $(MOODLE_ROOT)/lib/editor/tiny/plugins

# Mapping: source_directory:target_path_in_container
# Format: local_folder:path_inside_moodle
PLUGIN_MAPPINGS := \
	ai_manager:$(LOCAL_DIR)/ai_manager \
	moodle-block_ai_chat:$(BLOCKS_DIR)/ai_chat \
	moodle-block_ai_control:$(BLOCKS_DIR)/ai_control \
	moodle-qbank_questiongen:$(QUESTION_BANK_DIR)/questiongen \
	moodle-qtype_aitext:$(QUESTION_TYPE_DIR)/aitext \
	moodle-tiny_ai:$(TINY_PLUGINS_DIR)/ai

.PHONY: help up down restart clean zip dist clean-dist inject

help:
	@echo "Доступные цели:"
	@echo "  make up           - Запустить контейнеры (detached)"
	@echo "  make down         - Остановить и удалить контейнеры"
	@echo "  make restart      - Перезапустить контейнеры"
	@echo "  make clean        - Остановить и удалить контейнеры + анонимные тома"
	@echo "  make zip          - Собрать ZIP архивы для каждого плагина в каталоге dist/"
	@echo "  make clean-dist   - Удалить артефакты сборки (dist/)"
	@echo "  make inject       - Развернуть все плагины в контейнер Moodle"

# Start containers in detached mode
up:
	$(COMPOSE) -p $(PROJECT_NAME) up -d

# Stop and remove containers
down:
	$(COMPOSE) -p $(PROJECT_NAME) down

# Restart all containers (down + up)
restart: down up

# Full cleanup: stop containers and remove all volumes
clean:
	$(COMPOSE) -p $(PROJECT_NAME) down -v

# Create build artifacts directory
dist:
	mkdir -p $(DIST_DIR)

# Package each plugin into separate ZIP archive
zip: dist
	@echo "==> Packaging plugins into separate archives"
	@rm -f $(DIST_DIR)/*.zip
	@for dir in $(PLUGINS_DIRS); do \
		echo "  -> $$dir.zip"; \
		zip -rq "$(DIST_DIR)/$$dir.zip" "$$dir"; \
	done
	@echo "Done: all plugins packaged in $(DIST_DIR)/"

# Remove all build artifacts
clean-dist:
	rm -rf $(DIST_DIR)

# Deploy all plugins to running Moodle container
# Automatically finds container by bitnami/moodle:latest image
# Creates necessary directories and copies plugin files
inject:
	@echo "Deploying plugins to Moodle container..."
	@CONTAINER_NAME=$$(docker ps --filter "ancestor=bitnami/moodle:latest" --format "{{.Names}}" | head -n 1); \
	if [ -z "$$CONTAINER_NAME" ]; then \
		echo "Error: Moodle container not found!"; \
		exit 1; \
	fi; \
	echo "Found Moodle container: $$CONTAINER_NAME"; \
	for mapping in $(PLUGIN_MAPPINGS); do \
		SOURCE=$${mapping%%:*}; \
		TARGET=$${mapping#*:}; \
		PLUGIN_NAME=$${SOURCE#moodle-}; \
		echo "Deploying $$PLUGIN_NAME..."; \
		docker exec $$CONTAINER_NAME mkdir -p $$TARGET; \
		docker cp ./$$SOURCE/. $$CONTAINER_NAME:$$TARGET/; \
	done; \
	echo "All plugins deployed successfully to $$CONTAINER_NAME"; \
	echo "Don't forget to run Moodle upgrade at: Administration -> Notifications"
