# Grepmind Near — Development Process Reference

**Version:** 1.0  
**Date:** 27 October 2026  
**Owner:** Lead Android / Full-stack Developer  
**Status:** Active

This document is the single source of truth for how Grepmind Near is developed. Every agent and contributor must follow it. It defines the work cycle, quality gates, tooling, commit conventions, and the order in which features are built.

---

## 1. Core principles

1. **One authoritative architecture document.** The Product Requirements & Technical Specification (PRTS) and this process file govern all decisions. Agents do not change shared contracts without review.
2. **Vertical slices.** Build one end-to-end feature at a time (API → mobile screen → test → commit). Never build layers in isolation.
3. **Clean, polished, enterprise-grade code.** No TODOs left in production code, no commented-out blocks, no unused imports, consistent formatting, meaningful names.
4. **Premium UI/UX.** Use 2026 Material Design 3 tokens, premium cards, icons, banners, skeleton states, accessible touch targets, and smooth motion.
5. **Security from day one.** OTP limits, role-based authorization, object-level checks, no secrets in git, TLS everywhere, validated inputs.
6. **Small, reversible commits.** Commit after every verified slice with a clear progress message.

---

## 2. Repository layout (source of truth)

```text
grepmind-near/
├── DEVELOPMENT_PROCESS.md          # this file
├── PRTS.md                         # product requirements & technical spec
├── README.md
├── LICENSE
├── .gitignore
├── docker-compose.yml              # all local services
├── .env.example
├── Makefile                        # common dev targets
├── api/
│   └── openapi.yaml                # OpenAPI 3.x contract
├── apps/
│   ├── mobile/                     # Flutter Android app
│   ├── merchant-web/               # Next.js merchant dashboard
│   └── admin-web/                  # Next.js admin portal
├── backend/
│   ├── cmd/
│   │   ├── api/
│   │   └── worker/
│   ├── internal/
│   │   ├── auth/
│   │   ├── users/
│   │   ├── discovery/
│   │   ├── businesses/
│   │   ├── professionals/
│   │   ├── products/
│   │   ├── offers/
│   │   ├── availability/
│   │   ├── requests/
│   │   ├── reviews/
│   │   ├── moderation/
│   │   └── notifications/
│   ├── pkg/
│   ├── migrations/
│   └── go.mod
├── infrastructure/
│   ├── docker/
│   └── deployment/
└── docs/
    ├── architecture.md
    ├── adr/
    ├── security.md
    └── runbooks/
```

---

## 3. Recommended work cycle (every agent)

For every task:

1. **Write a small, explicit task.** Scope one vertical slice.
2. **Read the architecture documents.** Review PRTS.md, DEVELOPMENT_PROCESS.md, api/openapi.yaml, and any relevant ADRs before editing.
3. **Inspect existing code.** Read the files you will touch and their neighbors. Do not guess structure.
4. **Implement one vertical slice.** API route → handler → repository → migration → test → mobile screen → navigation → state.
5. **Run checks.** `gofmt`, `golangci-lint`, `go test`, `flutter analyze`, `flutter test`, Next.js lint/typecheck.
6. **Review the diff and security implications.** Check authorization boundaries, secrets, SQL injection risk, unsafe uploads.
7. **Update documentation and migration notes.** Keep OpenAPI and migrations in sync.
8. **Commit a small, reversible change.** Use the commit convention below.

---

## 4. Suggested agent responsibilities

| Role | Responsibilities |
|---|---|
| **Research Agent** | Compare libraries/hosting, verify docs, summarize trade-offs with sources. Does not change architecture directly. |
| **Backend Agent** | Go modules, repositories, handlers, migrations, tests. Follow OpenAPI contract. Add authorization and validation tests. |
| **Mobile Agent** | Flutter screens, navigation, Riverpod state, Dio networking, premium UI tokens, loading/empty/error/offline states. Keep API access separate from presentation. |
| **Web Agent** | Next.js pages, server actions, TypeScript strict, premium dashboard UI, authorization UI. |
| **QA / Security Agent** | Review authorization boundaries, edge-case tests, SQL injection, IDOR, privilege escalation, secrets, unsafe uploads. Report findings. |

Roles can be separate workflows or task-specific. They do not require distributed infrastructure.

---

## 5. Commit convention

Every commit message must describe progress. Format:

```
<type>: <short summary>

<body: what changed, why, and any notes>
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `security`, `perf`, `ci`, `build`.

Examples:

```
feat(backend): add nearby-business search endpoint

Implement GET /api/v1/businesses with PostGIS spatial search.
- Parameterized SQL, coordinate and radius validation
- Approved businesses only, bounded pagination
- Unit and integration tests added
Closes: nearby-search slice
```

```
feat(mobile): implement Explore screen with category list and skeleton states

- Premium Material Design 3 cards, icons, and banners
- Debounced search, skeleton loading, empty state
- Riverpod provider for nearby businesses
```

Never commit with vague messages like "update", "fix", or "wip". Every commit must be traceable to a slice.

---

## 6. Quality gates (must pass before commit)

### Backend (Go)
- `gofmt -l .` returns nothing
- `golangci-lint run ./...` passes
- `go test ./...` passes
- New endpoints have handler + repository + migration + test
- OpenAPI contract updated for any route change
- No secrets, no stack traces leaked to clients

### Mobile (Flutter)
- `flutter analyze` returns no errors
- `flutter test` passes
- Premium design tokens applied (colors, spacing, radius, typography)
- Skeleton, empty, loading, and error states present
- Touch targets ≥ 48 dp
- Images use cached/network thumbnails at display size

### Web (Next.js)
- `next lint` passes
- `tsc --noEmit` passes
- Premium dashboard UI with consistent tokens
- Server-side authorization enforced

### Git
- Working tree clean after commit (except intentional uncommitted work)
- Commit message follows convention
- No `.env`, `*.key`, `*.pem`, or secrets committed

---

## 7. Environment setup

### Prerequisites
- Docker & Docker Compose
- Go 1.22+
- Flutter 3.47.x + Dart 3.13.x
- Node.js 20+ + pnpm/npm
- PostgreSQL client (psql) for local inspection
- Android Studio (Windows) + WSL2 Ubuntu 24.04 (see Android-studio-guide.md)

### Local run (WSL)
```bash
# 1. Start infra
docker compose up -d

# 2. Run migrations
cd backend && go run cmd/api/main.go -migrate  # or use migration tool

# 3. Start API
cd backend && go run cmd/api/main.go

# 4. Start mobile (from WSL, emulator running on Windows)
cd apps/mobile && flutter pub get && flutter run -d emulator-5554

# 5. Start admin web
cd apps/admin-web && pnpm install && pnpm dev
```

### WSL / Android emulator bridging
See `Android-studio-guide.md`. Key points:
- Start Windows ADB server: `adb.exe -a start-server` (listens on 0.0.0.0:5037)
- Start Windows emulator from Android Studio Device Manager (`Medium_Phone_API_37.0`)
- WSL: `source ~/.bashrc` then `adb devices -l` and `flutter devices`
- **Important:** `ADB_SERVER_SOCKET` must use the WSL default gateway (recomputed per shell),
  not `10.255.255.254`. Each new shell: `export ADB_SERVER_SOCKET="tcp:$(ip route show default | awk '/^default/ {print $3; exit}'):5037"`
- Keep Flutter projects on the Linux filesystem, not `/mnt/d`

#### Known WSL2 limitation (validated Oct 2026)
- The Flutter app **installs and runs on the Windows emulator** (process visible via `adb shell ps`).
- The **VM Service / hot-reload channel** cannot connect from WSL across the ADB bridge
  (`Connection refused` on `127.0.0.1:<random-port>`). This is a dev-tooling-only limitation;
  the app itself runs on the device. Use full rebuild/reinstall for code changes rather than
  hot reload, or run Flutter from Windows for full dev tooling.
- The app targets `http://10.0.2.2:8080` (emulator alias for host). WSL2 localhost forwarding
  lets the Windows emulator reach the Go API running in WSL2 on port 8080.

---

## 8. Docker Compose services

| Service | Purpose | Port |
|---|---|---|
| postgres | PostgreSQL 16 + PostGIS | 5432 |
| api | Go API server | 8080 |
| worker | Go background worker | — |
| minio | S3-compatible object storage | 9000 / 9001 |
| admin-web | Next.js admin portal | 3000 |
| merchant-web | Next.js merchant dashboard | 3001 |

See `docker-compose.yml` for full configuration. Redis is intentionally excluded from MVP (added only when justified).

---

## 9. Branch strategy

- `main` — production-ready, protected. Deploys to production.
- `develop` — integration branch. Feature branches merge here.
- `feature/<slice>` — short-lived, one vertical slice. Deleted after merge.
- `hotfix/<issue>` — urgent production fix.

PRs require review and passing CI before merging to `develop`/`main`.

---

## 10. Definition of done (per slice)

- [ ] Code implements the feature per PRTS
- [ ] Tests added and passing
- [ ] Formatters/linters clean
- [ ] OpenAPI contract updated (if API changed)
- [ ] Migration added (if schema changed)
- [ ] Documentation/ADR updated (if architecture changed)
- [ ] Security review done (authorization, secrets, input validation)
- [ ] Committed with descriptive progress message
- [ ] Working tree clean

---

## 11. What agents must NOT do

- Do not execute unreviewed production database changes.
- Do not access production secrets or deploy to production without explicit authorization.
- Do not add libraries solely because they are popular; choose one tool per responsibility.
- Do not introduce Redis, microservices, payments, chat, or AI infra during MVP.
- Do not leave commented-out code, TODOs, or unused imports in committed code.
- Do not change shared contracts (OpenAPI, migrations, design tokens) without updating all consumers.

---

## 12. Escalation

If a task is ambiguous, conflicts with PRTS, or requires an architecture change, pause and ask the lead developer. Do not improvise shared contracts.
