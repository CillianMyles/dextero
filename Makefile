SHELL := /bin/bash
.DEFAULT_GOAL := help

DART ?= dart
FLUTTER ?= flutter
SERVERPOD ?= serverpod
CONTROL_URL ?= http://localhost:8080/
WORKSPACE ?= $(CURDIR)
APP_DEVICE ?= chrome
DEV_TOKEN_FILE := .dart_tool/dev-token

.PHONY: help doctor bootstrap tools token generate format format-check analyze \
	test test-core test-server test-app test-app-web test-cli check server app \
	app-web app-macos cli core dev dev-web dev-macos

help: ## Show the available developer commands.
	@printf "Dextero development\n\n"
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

doctor: ## Check the local tools used by the workspace.
	@command -v $(DART) >/dev/null || { echo "Missing Dart SDK"; exit 1; }
	@command -v $(FLUTTER) >/dev/null || { echo "Missing Flutter SDK"; exit 1; }
	@command -v openssl >/dev/null || { echo "Missing openssl (used for the dev token)"; exit 1; }
	@command -v curl >/dev/null || { echo "Missing curl (used by make dev readiness checks)"; exit 1; }
	@printf "Dart:    "; $(DART) --version
	@printf "Flutter: "; $(FLUTTER) --version | head -n 1
	@if [ "$(DEXTERO_MODEL_PROVIDER)" = "gemini" ] && [ -z "$(GEMINI_API_KEY)" ]; then \
	  echo "GEMINI_API_KEY is required when DEXTERO_MODEL_PROVIDER=gemini"; exit 1; \
	elif [ -n "$(GEMINI_API_KEY)" ] && [ "$(DEXTERO_MODEL_PROVIDER)" != "codex" ]; then \
	  echo "Gemini:  API key configured"; \
	else \
	  command -v codex >/dev/null || { echo "Missing Codex CLI (or configure GEMINI_API_KEY)"; exit 1; }; \
	  printf "Codex:   "; codex --version; \
	  codex login status >/dev/null || { echo "Codex is not authenticated; run 'codex login'"; exit 1; }; \
	fi
	@if command -v $(SERVERPOD) >/dev/null; then printf "Serverpod: "; $(SERVERPOD) version; else echo "Serverpod: not installed (make tools)"; fi

bootstrap: doctor ## Resolve every Dart and Flutter workspace dependency.
	@$(DART) pub get
	@echo "Workspace ready. Run 'make dev' or 'make server' + 'make cli'."

tools: ## Install the pinned Serverpod generator when it is missing.
	@command -v $(SERVERPOD) >/dev/null || $(DART) pub global activate serverpod_cli 3.4.13

$(DEV_TOKEN_FILE):
	@mkdir -p .dart_tool
	@umask 077; openssl rand -hex 32 > $(DEV_TOKEN_FILE)

token: $(DEV_TOKEN_FILE) ## Print the stable local development bearer token.
	@cat $(DEV_TOKEN_FILE)

generate: tools ## Regenerate the Serverpod server, client, and test protocol.
	@cd packages/server && $(SERVERPOD) generate
	@$(DART) format packages/server/lib/src/generated \
	 packages/server/lib/src/protocol \
	 packages/server/test/integration/test_tools

format: ## Format all Dart sources in the workspace.
	@$(DART) format .

format-check: ## Fail if any Dart source needs formatting.
	@$(DART) format --output=none --set-exit-if-changed .

analyze: ## Analyze all four workspace packages.
	@$(DART) analyze

test-core: ## Run core unit tests.
	@cd packages/core && $(DART) test

test-server: ## Run Serverpod endpoint integration tests.
	@cd packages/server && $(DART) test

test-app: ## Run Flutter widget tests on the local and web test devices.
	@cd packages/app && $(FLUTTER) test
	@cd packages/app && $(FLUTTER) test --platform chrome

test-app-web: ## Run Flutter widget tests in Chrome.
	@cd packages/app && $(FLUTTER) test --platform chrome

test-cli: ## Run CLI unit tests.
	@cd packages/cli && $(DART) test

test: ## Run every package test suite, including the Flutter web tests.
	@$(MAKE) --no-print-directory -j 4 test-core test-server test-app test-cli

check: format-check analyze test ## Run the same quality gate expected before review.

server: $(DEV_TOKEN_FILE) ## Run the local Serverpod host and Codex-backed core.
	@DEXTERO_CONTROL_TOKEN="$$(cat $(DEV_TOKEN_FILE))" \
	 DEXTERO_WORKSPACE="$(WORKSPACE)" \
	 $(DART) run packages/server/bin/server.dart

app: $(DEV_TOKEN_FILE) ## Run the Flutter client (Chrome by default; set APP_DEVICE).
	@token="$$(cat $(DEV_TOKEN_FILE))"; \
	 cd packages/app && \
	 $(FLUTTER) run -d "$(APP_DEVICE)" \
	   --dart-define="DEXTERO_CONTROL_TOKEN=$$token" \
	   --dart-define="DEXTERO_CONTROL_URL=$(CONTROL_URL)"

app-web: ## Run the Flutter web client in Chrome (start the server separately).
	@$(MAKE) --no-print-directory app APP_DEVICE=chrome

app-macos: ## Run the Flutter macOS client (start the server separately).
	@$(MAKE) --no-print-directory app APP_DEVICE=macos

cli: $(DEV_TOKEN_FILE) ## Run the terminal client (start the server separately).
	@DEXTERO_CONTROL_TOKEN="$$(cat $(DEV_TOKEN_FILE))" \
	 DEXTERO_CONTROL_URL="$(CONTROL_URL)" \
	 $(DART) run packages/cli/bin/dextero.dart $(if $(PROMPT),"$(PROMPT)",)

core: ## Run the core directly through Codex without Serverpod.
	@$(DART) run packages/core/bin/dextero_core.dart $(if $(PROMPT),"$(PROMPT)",)

dev: $(DEV_TOKEN_FILE) ## Start the server and Flutter client (Chrome by default).
	@set -e; \
	 token="$$(cat $(DEV_TOKEN_FILE))"; \
	 cleanup() { kill $$server_pid 2>/dev/null || true; }; \
	 trap cleanup EXIT INT TERM; \
	 DEXTERO_CONTROL_TOKEN="$$token" DEXTERO_WORKSPACE="$(WORKSPACE)" \
	   $(DART) run packages/server/bin/server.dart & server_pid=$$!; \
	 until curl --silent --output /dev/null "$(CONTROL_URL)"; do \
	   kill -0 $$server_pid 2>/dev/null || { echo "Server exited before becoming ready"; exit 1; }; \
	   sleep 0.25; \
	 done; \
	 cd packages/app && \
	 $(FLUTTER) run -d "$(APP_DEVICE)" \
	   --dart-define="DEXTERO_CONTROL_TOKEN=$$token" \
	   --dart-define="DEXTERO_CONTROL_URL=$(CONTROL_URL)"

dev-web: ## Start the server and Flutter web client together.
	@$(MAKE) --no-print-directory dev APP_DEVICE=chrome

dev-macos: ## Start the server and Flutter macOS client together.
	@$(MAKE) --no-print-directory dev APP_DEVICE=macos
