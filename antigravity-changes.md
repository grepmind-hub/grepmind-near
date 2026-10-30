# Antigravity Architecture & Implementation Changelog

> **Authoritative Handover Document**  
> **Platform:** Grepmind Near (Local Business & Service Discovery Platform — Odisha)  
> **Repository:** `d:/grepmind-near`  
> **Current Status:** All 22 Mobile Screens, Merchant Desktop Web Portal (`apps/merchant-web`), Admin Web Portal (`apps/admin-web`), Direct MinIO Photo Uploads (Option 4), and Real-Time SSE Booking Updates & Push Notifications (Option 5) are 100% complete, containerized, and verified.  
> **Next Active Task:** **Option 6 — Automated End-to-End Integration Testing & CI/CD Pipeline**.

---

## 1. System Architecture & Topology

Grepmind Near is structured as a modular monolith backend with unified reverse proxy routing and isolated frontends:

```
                                  ┌─────────────────────────────┐
                                  │      Client Applications    │
                                  ├──────────────┬──────────────┤
                                  │ Mobile App   │ Merchant Web │
                                  │ (Flutter/    │ (Next.js 14, │
                                  │  Android)    │  Port 3001)  │
                                  └───────┬──────┴───────┬──────┘
                                          │              │
                                          ▼              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                       Nginx Reverse Proxy (:80)                             │
├───────────────────┬───────────────────┬───────────────────┬─────────────────┤
│ Path: /admin/     │ Path: /merchant/  │ Path: /api/       │ Path: /media/   │
│ -> admin-web:3000 │ -> merchant-web:  │ -> api:8080/api/  │ -> minio:9000/  │
│                   │    3001           │                   │    grepmind-    │
│                   │                   │                   │    near/        │
└───────────────────┴───────────────────┴─────────┬─────────┴─────────────────┘
                                                  │
                                                  ▼
                                 ┌─────────────────────────────────┐
                                 │       Go REST API (:8080)       │
                                 │ (chi/mux, pgx/sqlx, JWT, RBAC)  │
                                 └────────┬──────────────┬─────────┘
                                          │              │
                                          ▼              ▼
                       ┌──────────────────────┐   ┌───────────────────────┐
                       │   PostgreSQL 16      │   │  MinIO Object Storage │
                       │   + PostGIS (:5432)  │   │  (S3 API :9000,       │
                       │                      │   │   Console :9001)      │
                       └──────────────────────┘   └───────────────────────┘
```

### Container & Port Mapping
| Service | Container Name | Internal Port | Host / Exposed Port | Routing URL |
|---|---|---|---|---|
| **Nginx Proxy** | `grepmind_nginx` | `80` | `0.0.0.0:80` | `http://localhost/` |
| **Go REST API** | `grepmind_api` | `8080` | `0.0.0.0:8080` | `http://localhost/api/` / `api.near.grepmind.com` |
| **Admin Portal** | `grepmind_admin_web` | `3000` | `0.0.0.0:3000` | `http://localhost/admin/` / `admin.near.grepmind.com` |
| **Merchant Portal** | `grepmind_merchant_web` | `3001` | `0.0.0.0:3001` | `http://localhost/merchant/` / `merchant.near.grepmind.com` |
| **PostgreSQL / PostGIS**| `grepmind_postgres` | `5432` | `0.0.0.0:5432` | `localhost:5432` (db: `grepmind_near`) |
| **MinIO S3 Storage** | `grepmind_minio` | `9000`, `9001` | `0.0.0.0:9000`, `9001` | `http://localhost:9000` (API), `:9001` (Console) |

---

## 2. Inventory of Completed Work & File Locations

### 2.1 22-Screen Flutter Mobile Application (`apps/mobile`)
Authoritative showcase: `Grepmind Near UI_UX App Showcase.png`.
All 22 screens are implemented using Material Design 3, Riverpod state management, Dio networking, and verified on Android emulator (`Pixel_8`):

1. **Splash Screen:** `apps/mobile/lib/core/screens/splash_screen.dart`
2. **Onboarding Carousel:** `apps/mobile/lib/core/screens/onboarding_screen.dart`
3. **Phone OTP Login:** Integrated in `onboarding_screen.dart`
4. **Location Selection Modal:** `apps/mobile/lib/core/screens/explore_screen.dart`
5. **City / Locality Picker:** Integrated in `explore_screen.dart` modal sheet
6. **Location Permission Welcome:** Permission primer bottom sheet
7. **Home / Explore Screen:** `apps/mobile/lib/core/screens/explore_screen.dart`
8. **Categories Directory:** `apps/mobile/lib/core/screens/categories_screen.dart`
9. **Search & Filter Results:** `apps/mobile/lib/core/screens/search_results_screen.dart`
10. **Nearby Interactive Map:** `apps/mobile/lib/core/screens/nearby_map_screen.dart`
11. **Business Profile & Tabs:** `apps/mobile/lib/core/screens/business_detail_screen.dart`
12. **Product Details Screen:** `apps/mobile/lib/core/screens/product_detail_screen.dart`
13. **Service Professional Profile:** `apps/mobile/lib/core/screens/service_pro_screen.dart`
14. **Service Request Submission:** `apps/mobile/lib/core/screens/service_request_screen.dart`
15. **Appointment Slot Scheduler:** `apps/mobile/lib/core/screens/booking_scheduler_screen.dart`
16. **Saved / Bookmarked Businesses:** `apps/mobile/lib/core/screens/saved_screen.dart`
17. **Customer Profile & Settings:** `apps/mobile/lib/core/screens/profile_screen.dart`
18. **Service Request Status Tracker:** `apps/mobile/lib/core/screens/service_request_status_screen.dart`
19. **Merchant Registration / Claim:** `apps/mobile/lib/core/screens/merchant_registration_screen.dart`
20. **Merchant Workspace Dashboard:** `apps/mobile/lib/core/screens/merchant_workspace_screen.dart`
21. **Merchant Catalog Management:** `apps/mobile/lib/core/screens/merchant_catalog_screen.dart`
22. **Merchant Hours & Coverage Setup:** `apps/mobile/lib/core/screens/merchant_hours_coverage_screen.dart`

### 2.2 Merchant Desktop Web Portal (`apps/merchant-web`)
- **Location:** `apps/merchant-web/`
- **Features:** Multi-branch switcher across Bhubaneswar, Cuttack, Puri, Jajpur; Bookings pipeline; Catalog editor; Operating hours & radius setup.
- **Role-Based Access Control (RBAC):** Backed by `backend/migrations/004_business_members.sql`. Supports `owner`, `manager`, and `staff`.
- **Team UI:** `apps/merchant-web/components/TeamManager.tsx` with "+ Add Team Member" modal and access revocation.
- **Authentication Gateway:** Passwordless phone OTP login (`AuthLoginView.tsx`) with strict merchant-level data isolation (no cross-store leakage).

### 2.3 Admin Web Portal (`apps/admin-web`)
- **Location:** `apps/admin-web/`
- **Design Tokens:** 2026 Reference UI Kit (`#2457D6` blue primary, `#0F766E` teal, 16px radius, Inter typography).
- **Core Modules:**
  1. **Graphical Metrics Hub (`GraphicalMetricsView.tsx`):** Bespoke SVG Area Chart (Daily Trends), Grouped Bar Chart (Multi-city GMV/volume comparison), Donut Chart (Category volume share), Diurnal Peak Booking Histogram (08:00–22:00), Unserved Location Demand Radar.
  2. **KYC & Listing Verification Queue (`VerificationQueueView.tsx`, `KYCReviewModal.tsx`):** Digital verification stamps for Trade Licenses, MSME Udyam, Artisan Board, and Clinical certificates.
  3. **Platform Merchant Registry (`BusinessesRegistryView.tsx`):** Directory of 14 businesses with live status badges and place-wise multi-city filtering.
  4. **Consumer Reports & Disputes (`ReportsDisputesView.tsx`):** 2 active inquiry tickets with dismiss and warning resolution actions.
  5. **Promotional Offers Moderation (`OffersModerationView.tsx`):** 4 active/pending campaigns with approve/reject actions.
  6. **Immutable Audit Trail (`AuditLogsView.tsx`):** Real-time log of administrative actions synced with PostgreSQL `audit_logs`.
  7. **Platform Admins & Access Management (`AdminUsersView.tsx`):** Active admin directory, root superadmin protections (`+910000000000`), and "+ Add Platform Admin" modal.

---

## 3. Critical Fixes & Resolutions Handover

### A. Resolution of Empty Data Tables in Admin Web
- **Root Cause:** In `apps/admin-web/lib/api.ts`, Axios was configured with `baseURL: http://localhost:8080/api/v1`. When accessing through Nginx at `http://localhost/admin/` (port 80), modern browser security blocked cross-origin requests to port 8080 (CORS). Requests failed silently, returning empty fallback arrays while sidebar counters displayed cached statistics.
- **Resolution:**
  - Updated `apps/admin-web/lib/api.ts`:
    ```ts
    const baseURL = typeof window !== 'undefined'
      ? '/api/v1'
      : (process.env.NEXT_PUBLIC_API_BASE_URL ?? 'http://api:8080/api/v1');
    ```
  - Added Axios request interceptor to dynamically inject `Authorization: Bearer <token>`.
  - Same-origin calls to `/api/v1/...` route directly through Nginx `location /api/ { proxy_pass http://api:8080/api/; }` on port 80 with zero CORS overhead.

### B. Admin RBAC Endpoints in Go Backend
- Implemented in `backend/internal/moderation/service.go` and wired in `backend/cmd/api/main.go`:
  - `GET /api/v1/admin/admins`: Queries `user_roles WHERE role = 'admin'`.
  - `POST /api/v1/admin/admins`: Upserts user in `users` and assigns `role = 'admin'` in `user_roles`. Logs to `audit_logs`.
  - `DELETE /api/v1/admin/admins/{userId}`: Revokes role; guards root superadmin (`+910000000000`) against deletion.

### C. Place-Wise Merchant Filtering
- Updated `BusinessesRegistryView.tsx`: Filter now matches both `b.city` and `b.address_text` against the selected city pill (`Bhubaneswar`, `Cuttack`, `Puri`, `Jajpur`), ensuring no store is omitted regardless of address format.

---

## 4. Critical Invariants & Rules (DO NOT BREAK)

Any AI model or developer continuing work on this repository **MUST** adhere to the following rules:

1. **Never Hardcode Port 8080 in Frontend Browsers:**
   - Always use relative `/api/v1` in `apps/admin-web` and `apps/merchant-web`.
   - Nginx handles reverse proxying on port 80. Hardcoding `:8080` re-introduces CORS browser blocks.
2. **Preserve Root Superadmin:**
   - Mobile number `+910000000000` is the root platform superadmin.
   - Never remove or allow deletion of this user.
3. **Data Isolation Across Merchants:**
   - In `apps/merchant-web` and backend merchant endpoints, queries must always be filtered by `business_id`.
   - Never expose catalog items, orders, or staff belonging to store A to store B.
4. **Sequential Database Migrations:**
   - Never edit past migration files (`001`, `002`, `003`, `004`, `005`, `006`, `007`).
   - Any schema changes must be added as a new migration (e.g., `008_...sql`).
5. **No Microservices or Heavy Queue Systems:**
   - Per `AGENTS.md`, stick to the modular Go monolith. Do not introduce Kafka, Redis, or Kubernetes.
6. **Streaming & Server-Sent Events Configuration:**
   - Go HTTP server streaming handlers require `WriteTimeout: 0` on `http.Server` to prevent timeout severance of long-lived event streams.
   - Nginx requires `proxy_buffering off;`, `proxy_cache off;`, and extended read timeouts (`proxy_read_timeout 3600s;`) to flush SSE frames immediately to clients.
   - When filtering SQL queries with optional UUID strings in Go, parse via `uuid.Parse()` and pass nullable pointers (`*uuid.UUID`) to prevent PostgreSQL `SQLSTATE 22P02` syntax exceptions.

---

## 5. Completed Implementation: Option 5 — Push Notifications & Real-Time Booking Updates (SSE)

### Goal:
Deliver zero-latency booking updates, service request notifications, and status tracking to merchant desktop and customer mobile apps without heavy WebSocket broker infrastructure.

### Architecture Plan:

```
[Customer Mobile / Flutter]          [Merchant Desktop / Next.js]
             │                                    │
             │ 1. POST /requests (New Booking)    │ 2. GET /api/v1/events?business_id=...
             ▼                                    │    (EventSource stream)
┌───────────────────────────────────────────────┐ │
│            Go REST API & SSE Hub              │ │
│   - Publish(event, payload, business_id)      │◄┘
│   - Write to PostgreSQL (notifications table) │
│   - Broadcast frame to active SSE clients     │
└──────────────────────┬────────────────────────┘
                       │
                       │ 3. Real-Time Push Frame: event: service_request.created
                       ▼
             [Merchant Web Portal]
               ├── Harmonious Web Audio dual-tone chime (playBookingChime)
               ├── Interactive Floating Booking Banner Alert ("Inspect Booking")
               ├── Notification Bell Unread Badge counter in Header
               └── Instant pipeline refresh without page reload
```

### Technical Deliverables Completed for Option 5:

1. **Database Migration (`backend/migrations/007_realtime_events_and_request_stages.sql`):**
   - Expanded `service_requests.status` check constraint: `('requested', 'accepted', 'in_progress', 'declined', 'rescheduled', 'cancelled', 'completed')`.
   - Created `notifications` table storing `id`, `user_id`, `business_id`, `title`, `body`, `event_type`, `reference_id`, `payload`, `is_read`, `created_at`.
   - Added performance indexes for user, business, and timestamp queries.
   - Seeded initial welcome notifications for active merchants.
2. **Backend SSE Hub & Service (`backend/internal/notifications/hub.go`):**
   - Implemented thread-safe `Hub` managing `*Client` connections with buffered channels.
   - `ServeSSE`: Sets SSE headers (`Content-Type: text/event-stream`, `Cache-Control: no-cache`), sends `event: connected` handshake, periodic 15s keepalive ping (`: ping {timestamp}`), and streams events to clients matching `business_id`, `request_id`, or `user_id`.
   - `Publish`: Dispatches events to active clients and persists notification to PostgreSQL with safe UUID handling.
   - `ListNotifications`: Returns paginated notifications.
   - `MarkAsRead`: Sets `is_read = true`.
3. **API Wiring & HTTP Server (`backend/cmd/api/main.go`):**
   - Configured `http.Server.WriteTimeout = 0` to sustain indefinite streaming connections.
   - Registered endpoints: `GET /api/v1/events`, `GET /api/v1/notifications`, `POST /api/v1/notifications/{id}/read`, `POST /api/v1/notifications/broadcast-test`.
   - Wired `notifHub.Publish` inside `handleCreateServiceRequest` (`service_request.created`).
   - Wired `notifHub.Publish` inside `merchantRequestStatus` (`service_request.status_updated`).
4. **Nginx Reverse Proxy Streaming Config (`infrastructure/docker/nginx/nginx.conf`):**
   - Added `proxy_buffering off;`, `proxy_cache off;`, `proxy_read_timeout 3600s;`, and `proxy_send_timeout 3600s;` under `location /api/`.
5. **Merchant Desktop Web Portal (`apps/merchant-web`):**
   - `apps/merchant-web/lib/api.ts`: Added `subscribeToEvents`, `playBookingChime()`, `updateServiceRequestStatus()`, `fetchNotifications()`, and `markNotificationAsRead()`.
   - Web Audio API dual-tone chime (sine wave D5 -> A5 harmonious frequencies) plays on new booking reception without external audio files.
   - `apps/merchant-web/components/Header.tsx`: Integrated Notification Bell with real-time unread badge counter, alert dropdown, relative timestamps, and mark-as-read interaction.
   - `apps/merchant-web/app/page.tsx`: Added real-time floating booking banner with "Inspect Booking" action; updates bookings pipeline state immediately upon receipt.
6. **Mobile App Live Tracking (`apps/mobile`):**
   - `apps/mobile/lib/core/screens/service_request_status_screen.dart`: Integrated `_statusPollTimer` running periodic 4-second checks with auto-cancel on terminal states (`completed`, `cancelled`, `declined`) and clean lifecycle cancellation in `dispose()`.
7. **OpenAPI 3.0 Contract (`api/openapi.yaml`):**
   - Added `notifications` tag documenting `/events`, `/notifications`, `/notifications/{id}/read`, and `/notifications/broadcast-test`.

---

## 6. Implementation Verification & Milestone Matrix

| Milestone | Component | Status | Verification Evidence |
|---|---|---|---|
| **1. 22-Screen UI Showcase** | Mobile App (`apps/mobile`) | ✅ Complete | Verified on Android emulator across all 22 screens matching `ref-image/` and `Grepmind Near UI_UX App Showcase.png`. |
| **2. Merchant Web Portal** | Desktop Web (`apps/merchant-web`) | ✅ Complete | Next.js 14 container on port 3001, reverse proxied at `http://localhost/merchant/`. Passwordless Phone OTP, multi-branch switcher, bookings pipeline, team RBAC. |
| **3. Admin Web Portal** | Admin Web (`apps/admin-web`) | ✅ Complete | Next.js 14 container on port 3000, reverse proxied at `http://localhost/admin/`. Charts (SVG area, bar, donut, hourly), KYC review modal, Reports, Audit trail, Admin RBAC. |
| **4. Direct Photo Upload to MinIO** | Storage & API (`/media/upload`) | ✅ Complete | MinIO S3 integration (`minio-go/v7@v7.0.66`), Nginx `/media/` proxy, PostgreSQL migration `006_media_uploads.sql`, OpenAPI spec, Merchant Web Catalog dropzone with preview, verified HTTP 201 Created & HTTP 200 OK asset serving. |
| **5. Push Notifications & Real-Time Updates** | Backend SSE & Web/Mobile Alerts | ✅ Complete | Go SSE hub (`http.Flusher`), migration `007_realtime_events_and_request_stages.sql`, Nginx unbuffered streaming, Merchant Web Audio chime & notification bell, floating banner alert, Mobile Screen 18 live tracking, verified HTTP 200 event streaming & PostgreSQL persistence. |
| **6. Hospitality & Food Delivery Expansion** | Mobile App & Discovery Backend | ✅ Complete | Migration `008_hospitality_and_food_delivery.sql`, `hotel` category, delivery/table/room booking schema, dynamic CTAs, multi-item Food Cart & Checkout, Table Reservation modal, Hotel Room booking sheet, Spice Garden & Mayfair Resort seed data, 100% clean `flutter analyze`. |

---

## 7. What Next: Option 6 — Automated End-to-End Integration Testing & CI/CD Pipeline

With Real-Time Streaming and Notifications verified, the next recommended step is **Automated Integration Testing & CI/CD Pipeline**:

1. **Go API Automated Test Suite:**
   - Add end-to-end integration tests in `backend/tests/` exercising Phone OTP login, booking creation, SSE event delivery, MinIO photo uploads, and Admin KYC approval flows.
2. **Merchant & Admin Web Smoke Tests:**
   - Headless Playwright / Cypress suite verifying Next.js login gateway, branch switching, team invitation, and verification queue actions.
3. **Flutter Integration Driver Tests:**
   - Automated driver scripts validating customer booking submission and live status transitions.
4. **Unified Docker Compose Test Target:**
   - Add `make test-all` or `docker compose -f docker-compose.test.yml up --exit-code-from test-runner` for deterministic regression prevention.

---

## 8. Recommended Git Commit Message

When committing Option 5 changes, use the following standardized message:

```git
feat: implement real-time SSE event streaming and push notifications (Option 5)

- Add database migration 007_realtime_events_and_request_stages.sql adding in_progress and rescheduled statuses and notifications table
- Implement Go standard-library SSE hub in backend/internal/notifications/hub.go with 15s keepalive pings and channel fanout
- Configure http.Server.WriteTimeout = 0 in backend/cmd/api/main.go to support long-lived text/event-stream connections
- Register GET /api/v1/events, GET /api/v1/notifications, POST /api/v1/notifications/{id}/read, and POST /api/v1/notifications/broadcast-test
- Configure Nginx unbuffered reverse proxying with proxy_buffering off; and proxy_read_timeout 3600s;
- Update api/openapi.yaml with notifications tag, streaming schema, and notification endpoints
- Integrate real-time EventSource listener, floating alert banner, and Web Audio API chime in apps/merchant-web
- Add interactive Notification Bell with unread counter and mark-as-read dropdown in apps/merchant-web/components/Header.tsx
- Add live status polling and lifecycle disposal in Flutter Screen 18 (apps/mobile/lib/core/screens/service_request_status_screen.dart)
- Verify end-to-end event broadcast, audio chime triggering, and database persistence
```
