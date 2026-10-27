# Grepmind Near

Local discovery platform connecting customers with nearby shops, products, offers, and service professionals.

## Repository structure

- `apps/mobile` — Flutter Android customer app
- `apps/merchant-web` — Next.js merchant dashboard
- `apps/admin-web` — Next.js admin portal
- `backend` — Go modular monolith API + worker
- `api/openapi.yaml` — OpenAPI 3.x contract
- `docker-compose.yml` — local services

## Getting started

See `DEVELOPMENT_PROCESS.md` for the development process, quality gates, and environment setup.

```bash
# Start infrastructure
docker compose up -d

# Run backend
cd backend && go run cmd/api/main.go

# Run mobile (WSL, emulator on Windows)
cd apps/mobile && flutter pub get && flutter run -d emulator-5554

# Run admin web
cd apps/admin-web && pnpm install && pnpm dev
```

## Environments

Local (Docker Compose) → Staging → Production. See `docs/` and `infrastructure/deployment/`.
