.PHONY: help lint format fix typecheck test test-fast test-failed coverage mutation audit deptry deadcode licenses check sync deps outdated upgrade uv-update hooks-install hooks-run hooks-update clean firewall-refresh

.DEFAULT_GOAL := help

help: ## Display available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-16s\033[0m %s\n", $$1, $$2}'

# --- Code quality ---

lint: ## Run Ruff linter
	uv run ruff check .

format: ## Run Ruff formatter
	uv run ruff format .

fix: ## Auto-fix lint issues and reformat
	uv run ruff check --fix .
	uv run ruff format .

typecheck: ## Run type checker (ty)
	uv run ty check src

# --- Testing ---

test: ## Run tests with coverage
	uv run pytest

test-fast: ## Run tests without coverage (faster)
	uv run pytest --no-cov

test-failed: ## Re-run only failed tests
	uv run pytest --lf --no-cov

coverage: ## Generate HTML coverage report (htmlcov/index.html)
	uv run pytest --cov-report=html

mutation: ## Run mutation testing (mutmut) - slow, not part of `make check`
	uv run mutmut run

audit: ## Scan dependencies for known vulnerabilities
	uv audit

deptry: ## Check for unused/missing/misplaced dependencies
	uv run deptry .

deadcode: ## Scan for unused code (vulture)
	uv run vulture

licenses: ## Verify dependency OSS license compatibility (pip-licenses)
	uv run pip-licenses

# --- CI gate ---

check: lint format typecheck test audit deptry deadcode licenses ## Run all checks (CI gate)

# --- Utilities ---

sync: ## Fetch remote and sync all dependencies including dev
	git fetch --tags --prune origin
	git status
	uv sync

deps: ## Show full dependency tree
	uv tree

outdated: ## Show outdated packages in dependency tree
	uv tree --outdated

upgrade: ## Upgrade all dependencies to latest compatible versions and sync
	uv sync --upgrade

uv-update: ## Update uv itself to the latest version
	uv self update

firewall-refresh: ## Re-resolve and refresh the devcontainer firewall allowlist (e.g. before OSV-dependent checks)
	sudo /usr/local/bin/init-firewall.sh

hooks-install: ## Install pre-commit hooks into the local git repository
	uv run prek install --hook-type pre-commit --hook-type commit-msg --hook-type pre-push

hooks-run: ## Run all pre-commit hooks against all files
	uv run prek run --all-files

hooks-update: ## Update pre-commit hook versions to latest
	uv run prek autoupdate

clean: ## Remove caches and generated files
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name .pytest_cache -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name .ruff_cache -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name htmlcov -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name .hypothesis -exec rm -rf {} + 2>/dev/null || true
	find . -type f \( -name "*.pyc" -o -name ".coverage" \) -delete
	rm -f coverage.xml
	rm -rf mutants .mutmut-cache
