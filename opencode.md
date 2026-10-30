# opencode.md — Grepmind Near Project Context

## Project Summary

Grepmind Near is a local business and service discovery platform. Everything nearby. One tap away.

## Technology Stack

| Layer | Technology | Details |
|-------|-----------|---------|
| Mobile App | Flutter 3.47.8 / Dart 3.13.7 | Riverpod state, Dio networking, GoRouter navigation |
| Backend | Go REST API | chi router, pgx/sqlx, PostgreSQL + PostGIS |
| Merchant Portal | Next.js 14 | Port 3001, reverse proxied at `/merchant/` |
| Admin Portal | Next.js 14 | Port 3000, reverse proxied at `/admin/` |
| Object Storage | MinIO | S3-compatible, port 9000/9001 |
| Database | PostgreSQL 16 + PostGIS | Port 5432 |
| Reverse Proxy | Nginx | Port 80, path-based routing |
| API Contract | OpenAPI | `api/openapi.yaml` |

## Milestone Status (per antigravity-changes.md)

| Milestone | Status |
|-----------|--------|
| 1. 22-Screen UI Showcase | ✅ Complete |
| 2. Merchant Web Portal | ✅ Complete |
| 3. Admin Web Portal | ✅ Complete |
| 4. Direct Photo Upload to MinIO | ✅ Complete |
| 5. Push Notifications & Real-Time Booking Updates | ✅ Complete |
| 6. Hospitality, Hotels & Food Delivery | ✅ Complete |
| **7. Automated E2E Integration Testing & CI/CD** | ⏳ Next |

## Architecture

```
Nginx (:80)
├── /admin/     -> admin-web:3000
├── /merchant/  -> merchant-web:3001
├── /api/       -> api:8080/api/
└── /media/     -> minio:9000/grepmind-near/
```

## Local Development (WSL2 + Windows Emulator)

- Android emulator runs on Windows (`Medium_Phone_API_37.0`)
- Flutter runs inside WSL2 (Ubuntu 24.04)
- ADB bridge: Windows `adb.exe -a start-server` listens on `0.0.0.0:5037`
- WSL client connects via `ADB_SERVER_SOCKET=tcp:<gateway-ip>:5037`
- `flutter run -d emulator-5554` from WSL

## Key Files

| Purpose | Path |
|---------|------|
| Project docs | `AGENTS.md` |
| Dev guide | `Android-studio-guide.md` |
| Changelog | `antigravity-changes.md` |
| OpenAPI spec | `api/openapi.yaml` |
| Docker Compose | `docker-compose.yml` |
| Mobile screens | `apps/mobile/lib/core/screens/` |
| Go backend | `backend/internal/` |
| Merchant web | `apps/merchant-web/` |
| Admin web | `apps/admin-web/` |

## Critical Invariant Rules

1. Never hardcode port 8080 in frontend browsers — use relative `/api/v1`
2. Preserve root superadmin (`+910000000000`) — never delete
3. Data isolation across merchants — always filter by `business_id`
4. Sequential database migrations — never edit past migrations; add new `00X_...sql`
5. No microservices, Redis, Kafka, Kubernetes — modular Go monolith
6. SSE streaming requires `WriteTimeout: 0` in Go HTTP server
7. Nginx SSE: `proxy_buffering off; proxy_cache off; proxy_read_timeout 3600s;`
