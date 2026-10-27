.PHONY: help up down migrate test lint fmt tidy mobile-android mobile-analyze mobile-test admin-dev admin-lint admin-typecheck

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

up: ## Start all local services
	docker compose up -d

down: ## Stop all local services
	docker compose down

logs: ## Follow service logs
	docker compose logs -f

migrate: ## Run database migrations
	cd backend && go run ./cmd/api -migrate

test-backend: ## Run Go tests
	cd backend && go test ./...

lint-backend: ## Lint Go code
	cd backend && golangci-lint run ./... || gofmt -l .

fmt-backend: ## Format Go code
	cd backend && gofmt -w .

tidy-backend: ## Tidy Go modules
	cd backend && go mod tidy

mobile-analyze: ## Flutter analyze
	cd apps/mobile && flutter analyze

mobile-test: ## Flutter tests
	cd apps/mobile && flutter test

mobile-android: ## Run Flutter on Android emulator
	cd apps/mobile && flutter run -d emulator-5554

admin-dev: ## Run admin web dev server
	cd apps/admin-web && pnpm dev

admin-lint: ## Lint Next.js admin
	cd apps/admin-web && pnpm lint

admin-typecheck: ## TypeScript check admin
	cd apps/admin-web && pnpm exec tsc --noEmit
