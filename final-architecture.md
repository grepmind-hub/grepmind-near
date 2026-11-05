Below is the Final Master Prompt for Codex for the next major development phase of Grepmind Near — Unified Commerce, Merchant Operations & Shared Delivery Network.

It covers all three mobile modes, payment integration, real-time tracking, database architecture, premium UI/UX, performance optimization, phase-wise implementation, and mandatory validation.

The prompt is designed for your existing repository at D:\grepmind-near, using Flutter, Go, PostgreSQL/PostGIS, Next.js, Docker Compose, and your existing SSE infrastructure.

Important: Codex must audit the current implementation before writing code. Each phase requires your approval, implementation, automated tests, and validation before proceeding.

You are the Principal Software Architect, Senior Flutter Engineer, Senior Go Backend Engineer, PostgreSQL/PostGIS Engineer, Payment Systems Engineer, DevOps Engineer, QA Automation Engineer, and Premium Mobile UI/UX Designer for GREPMIND NEAR.

PROJECT: Grepmind Near — Unified Local Commerce, Merchant Operations & Shared Rider Delivery Network
REPOSITORY: D:\grepmind-near
PLATFORM: Existing Flutter Android application + existing Next.js merchant/admin web portals
BACKEND: Existing Go modular monolith
DATABASE: PostgreSQL 16 + PostGIS
INFRASTRUCTURE: Docker Compose, Nginx, MinIO
REAL-TIME: Existing SSE infrastructure; introduce FCM where needed
DEVELOPMENT ENVIRONMENT: Windows Codex Desktop, WSL for Flutter/Android builds when configured.

====================
A. NON-NEGOTIABLE EXECUTION CONTRACT
====================
1. PHASE 0 IS READ-ONLY. Audit the actual repository, routes, screens, schema, migrations, tests, environment and implementation status. Do not assume prior completion claims are correct.
2. The app reportedly contains 28 mobile screens. Enumerate actual routes and screen files. Compare existing functionality with proposed capabilities and identify REUSE, EXTEND, NEW, MERGE, or DEFER. Do not assume 28+29=57.
3. First produce a detailed architecture report, diagrams, visual navigation specification, implementation backlog, dependencies, risks, and acceptance criteria. STOP and wait for explicit user approval.
4. After approval, implement ONE PHASE AT A TIME. For every phase: plan -> implement -> test -> inspect UI -> validate API/database/security/performance -> report -> STOP for approval. Never automatically start the next phase.
5. Never claim tests or screens are verified without executing checks. Distinguish implemented, tested, manually verified, blocked, and unverified.
6. Preserve existing features, authentication, data, bookings, merchant isolation, and admin controls. No destructive migrations.
7. Keep ONE Flutter mobile application with Customer, Merchant, and Rider modes. DO NOT create a separate rider app.
8. Keep ONE Go modular monolith. Do not introduce microservices, Kafka, RabbitMQ, or other heavy infrastructure without a measured need and approval.
9. Preserve relative /api/v1 routing in browser portals; do not hardcode backend ports.
10. Preserve merchant business_id isolation and protect root superadmin.
11. Use sequential additive migrations after inspecting existing migration numbering.
12. Never expose secrets, signing keys, UPI credentials, or sensitive identity documents.
13. Payment integration must start in sandbox. Real-money payments, merchant settlement, and rider payouts remain disabled until explicitly approved and provider/legal requirements are confirmed.
14. Use the existing WSL Flutter/Android environment. Do not rewrite local.properties to Windows paths or regenerate signing keys. The release build currently needs a separately managed upload/release key.
15. Document every decision, tradeoff, change, validation result, and outstanding issue.

====================
B. COMPLETE SYSTEM ARCHITECTURE
====================
Design and implement incrementally:

ONE FLUTTER APPLICATION
  CUSTOMER MODE
    Discovery, catalog, cart, addresses, checkout, orders, tracking, profile
  MERCHANT MODE
    Dashboard, orders, preparation, rider handover, catalog, earnings, profile
  RIDER MODE
    Dashboard, offers, navigation, pickup, active delivery, earnings, profile

EXISTING NEXT.JS PORTALS
  Merchant desktop portal: detailed catalog, staff, branch operations, reporting
  Admin portal: KYC, rider verification, live dispatch, disputes, payment operations

EXISTING NGINX
  /api/v1 -> Go backend
  /admin -> Admin Next.js
  /merchant -> Merchant Next.js
  /media -> MinIO

GO MODULAR MONOLITH
  Auth & RBAC
  Discovery & category capabilities
  Commerce & orders
  Payment gateway abstraction
  Merchant operations
  Rider onboarding
  Dispatch & assignment
  Delivery lifecycle
  Location tracking
  Settlement ledger
  Notifications & outbox
  Auditing & analytics

POSTGRESQL 16 + POSTGIS
  Transactional state, spatial rider search, order history, payment events,
  dispatch offers, tracking snapshots, settlement entries, audit records

EXTERNAL SERVICES
  UPI-capable payment gateway
  Firebase Cloud Messaging
  Optional maps/geocoding/routing provider
  Optional SMS/telephony provider

Produce Mermaid architecture diagrams, sequence diagrams, entity relationships, and event flows. Diagrams must match real implementation.

====================
C. ROLE-BASED MODE SWITCHING
====================
A single authenticated user may hold multiple roles:
- Customer: default
- Merchant owner/manager/staff: only with authorized business membership
- Rider: only after approval

Mode switch is a presentation/workspace choice, NOT a security grant.

Requirements:
- Profile -> Switch workspace
- Customer / Merchant / Delivery Partner modes
- Merchant branch selector when authorized
- Preserve existing session and account
- Fetch current roles/permissions from backend
- Enforce authorization on every API
- Prevent unauthorized mode activation
- Handle revoked roles, expired sessions, offline states and active deliveries
- Preserve active rider tracking when switching UI modes only when authorized and required; never silently terminate an active trip or run unnecessary GPS
- A rider with an active delivery must receive clear warnings before going offline or signing out
- Customer mode must never access another customer's order or rider tracking
- Merchant users must never access unrelated business data
- Separate role-scoped Riverpod state and invalidate it on role/business change

====================
D. PREMIUM BOTTOM NAVIGATION DESIGN
====================
CUSTOMER MODE:
  Home | Explore | Nearby | Orders | Profile

MERCHANT MODE:
  Dashboard | Orders | Catalog | Earnings | Profile

RIDER MODE:
  Dashboard | Offers/Deliveries | Map/Navigation | Earnings | Profile

Move Saved/Bookmarks from the customer bottom navigation into Profile.
Preserve the existing Saved screen and APIs.

Profile:
  Account information
  Saved businesses
  Saved addresses
  My orders
  Workspace switcher
  Become a delivery partner
  Merchant workspace
  Notifications
  Settings and privacy
  Support

Design a premium Material 3 interface:
- Consistent design tokens, typography, spacing and radii
- Brand blue accent, accessible neutral surfaces
- Light and dark mode
- 48dp minimum recommended touch targets
- Clear active navigation state
- Loading, skeleton, empty, offline, error and retry states
- No horizontal overflow or clipped labels
- Smooth role transitions
- Appropriate badges for pending orders/offers
- Navigation should respect safe areas, keyboard and Android back behavior
- Support text scaling and accessibility semantics
- Reuse existing components before creating new ones

Create a navigation matrix, screen wireframes or mockups using available project tools, and screenshots from a running emulator where possible. Never claim a design was visually verified without inspecting the rendered UI.

====================
E. CUSTOMER FLUTTER CAPABILITIES
====================
1. Restaurant/shop catalog: products, availability, stock, merchant eligibility, category capabilities
2. Cart: quantities, minimum order, stock validation, totals
3. Delivery address: saved addresses, map pin, landmark, phone/contact
4. Checkout: item subtotal, delivery fee, taxes, discounts, final server-calculated amount, UPI-capable gateway
5. Payment result: pending, verified paid, failed, cancelled, retry
6. Order tracking: timeline, preparation, rider assignment, GPS, ETA, stale location state
7. Order history: details, invoice/receipt, reorder, support
8. Delivery verification: delivery OTP, confirmation and dispute handling

Reuse existing catalog, product, business, authentication and profile functionality wherever applicable.

====================
F. RIDER FLUTTER CAPABILITIES
====================
1. Onboarding: reuse login, rider application, identity and vehicle verification
2. Dashboard: approved status, online/offline, active job, operational alerts
3. Delivery offer: pickup, drop-off zone, estimated payout, timeout, accept/decline
4. Pickup navigation: merchant route, arrival, contact options
5. Pickup confirmation: order code or QR, merchant handover
6. Active delivery: navigation, customer contact, foreground location sharing, ETA
7. Delivery completion: OTP, delivery proof, failed-delivery workflow
8. Earnings: completed deliveries, adjustments, payout history
9. Support: incident reporting, safety, emergency and help

Start with one active delivery per rider.
Do not implement batching or multi-order routing initially.
Ensure background tracking is permission-aware, consent-based, and compliant with Android/Play requirements.

====================
G. MERCHANT FLUTTER CAPABILITIES
====================
1. Registration and business claim (reuse existing)
2. Merchant dashboard (extend existing)
3. Incoming order queue
4. Order details and customer instructions
5. Preparation state management
6. Rider assignment and arrival status
7. Pickup handover confirmation
8. Product/menu/catalog management (reuse existing)
9. Business hours, stock, availability and delivery settings
10. Earnings and settlement overview
11. Order history and operational analytics
12. Support, cancellation, refunds and disputes

Preserve existing merchant web portal. Mobile mode should focus on fast daily operations; desktop retains advanced administration.

====================
H. ORDER, PAYMENT, DELIVERY STATE MACHINES
====================
Implement distinct state machines, not one overloaded status field.

ORDER:
created -> awaiting_payment -> payment_confirmed -> merchant_accepted
-> preparing -> ready_for_pickup -> picked_up -> delivered

Include legal transitions for rejected, cancelled, expired, refunded and failed fulfillment.

PAYMENT:
created -> pending -> authorized/captured
Include failed, cancelled, expired, partial_refund, refunded and dispute states.
Do not treat client-side payment callbacks as proof of payment.

DELIVERY:
unassigned -> offered -> accepted -> arriving_pickup -> at_pickup
-> picked_up -> arriving_dropoff -> at_dropoff -> completed
Include expired_offer, reassigned, cancelled, failed_delivery and return flows.

Specify:
- Allowed transitions and actor permissions
- Preconditions, side effects and compensation
- Idempotency and concurrency control
- Immutable audit trail
- Order/payment/delivery consistency rules
- Recovery after process crash, lost connection and duplicate events

====================
I. GO API CONTRACTS
====================
Inspect existing routes before adding endpoints. Prefer extending existing API contracts and avoid duplicate resources.

Suggested endpoints:
POST /api/v1/orders
GET /api/v1/orders/{id}
POST /api/v1/orders/{id}/payment-attempts
POST /api/v1/payments/webhooks/{provider}
POST /api/v1/merchant/orders/{id}/accept
POST /api/v1/merchant/orders/{id}/reject
POST /api/v1/merchant/orders/{id}/ready
POST /api/v1/merchant/orders/{id}/handover
POST /api/v1/rider/applications
GET /api/v1/rider/profile
POST /api/v1/rider/availability
GET /api/v1/rider/offers
POST /api/v1/rider/offers/{id}/accept
POST /api/v1/rider/offers/{id}/decline
GET /api/v1/rider/deliveries/active
POST /api/v1/rider/deliveries/{id}/location
POST /api/v1/rider/deliveries/{id}/pickup
POST /api/v1/rider/deliveries/{id}/complete
GET /api/v1/orders/{id}/tracking
GET /api/v1/events
GET /api/v1/rider/earnings
GET /api/v1/merchant/settlements
GET /api/v1/admin/dispatch
POST /api/v1/admin/deliveries/{id}/assign

For each endpoint define:
- Request/response schemas
- Auth and business/order ownership rules
- Validation and status codes
- Idempotency behavior
- Rate limits
- Pagination where applicable
- Audit events
- Contract and integration tests

====================
J. POSTGRESQL + POSTGIS DATA MODEL
====================
Inspect current schema and avoid duplicating existing tables.

Candidate logical entities:
orders
order_items
carts / cart_items (if persistence is needed)
customer_addresses
payment_attempts
payment_provider_events
refunds
riders
rider_documents
rider_availability
delivery_zones
deliveries
delivery_offers
rider_latest_locations
rider_location_history (retention-limited)
delivery_events
delivery_proofs
merchant_settlement_entries
rider_payout_entries
financial_ledger_entries
outbox_events
notification_tokens
audit_logs

Requirements:
- UUID foreign keys and existing nullable UUID conventions
- Monetary amounts in integer minor units, never floating-point money
- Currency and tax breakdown
- Snapshot product name/price/address at checkout
- Unique provider event IDs
- Provider reference uniqueness
- Proper FK/check/unique constraints
- Partial unique index for active rider assignment where appropriate
- Spatial GiST indexes
- geography(Point,4326) for meter-distance calculations
- Zone polygons with spatial indexes
- Transaction-safe dispatch assignment
- Retention/cleanup for GPS history
- Avoid storing sensitive documents directly in ordinary public tables
- MinIO private document storage and authorized access
- Sequential additive migrations and rollback strategy
- Seed only clearly marked development fixtures

Produce an ER diagram and migration-by-migration plan before coding.

====================
K. REAL-TIME TRACKING + SSE + FCM
====================
Rider device:
  Android location service -> authenticated HTTPS location upload
  -> Go validation -> latest position in PostGIS
  -> authorized order-scoped event -> SSE -> customer/operations

FCM:
  New order to merchant
  New offer to rider
  Order status to customer
  Delivery completion
  Important operational exceptions

SSE:
  Foreground status updates and live tracking
  Reuse existing SSE hub and Nginx configuration
  Add durable sequence IDs and snapshot-on-reconnect where necessary
  Avoid multiple unnecessary connections
  Scope delivery events to assigned rider, order owner, merchant and authorized admins

Location rules:
- No GPS tracking for ordinary customer browsing
- No continuous GPS for merchant mode
- Rider online/available location strategy must be explicitly designed and consented
- Active delivery tracking: initial target around 10-15 seconds, configurable
- Adaptive update rate for stationary rider
- Stop tracking after completion/cancellation when no other active authorized task
- Handle background service, battery restrictions, network outages and retries
- Validate GPS accuracy, timestamps, impossible jumps and delivery ownership
- Show last updated time and stale-location UI
- Never expose rider home location or unrelated trips
- Implement retention and deletion policy
- FCM delivery is not guaranteed; fetch authoritative state from API
- Do not send sensitive GPS coordinates in general push payloads

FCM setup must support Android app configuration, device token registration/rotation, secure server credentials, notification channels, Android notification permissions, and tests. Do not confuse Firebase Cloud Messaging with Firebase Authentication.

====================
L. UPI GATEWAY, LEDGER AND SETTLEMENT
====================
Introduce provider abstraction so gateway can be changed without rewriting commerce.

Evaluate Razorpay Route and Cashfree Easy Split or suitable alternatives for marketplace payments and merchant settlements.

Sandbox first:
- Server creates gateway order
- Customer authorizes UPI payment
- Backend verifies signed webhook and provider status
- Idempotent event handling
- Handle pending, success, failure and delayed events
- Refund and partial refund workflows
- Ledger records merchant payable, rider payable, Grepmind revenue, provider fees, refunds and adjustments
- Reconciliation reports and provider references
- Separate merchant settlement from rider payout
- No manual unsupported split settlements
- Never store UPI PIN, card credentials or gateway secrets in Flutter
- Server-authoritative pricing, discounts, fees and taxes
- Payment provider eligibility and merchant-of-record arrangement must be approved before production
- Do not enable live transactions without explicit user authorization

====================
M. PERFORMANCE ENGINEERING
====================
57 screens is not inherently a performance problem. Verify actual screen count first.

Architecture:
- Feature-based Flutter modules
- Lazy screen construction
- Riverpod autoDispose where appropriate
- Isolate state by user role, business and order
- Avoid global rebuilds
- Paginated product and order lists
- Cached/compressed images and thumbnails
- Load maps only on relevant screens
- Dispose map controllers, SSE subscriptions, streams and timers
- Avoid unnecessary background polling
- Limit concurrent networking and retry storms
- Reduce unnecessary dependencies and asset sizes
- Use Flutter profile/release builds for measurements

REAL-TIME SERVICE ISOLATION:
Customer browsing: GPS off, lightweight order notifications
Customer tracking: order-scoped SSE, GPS upload off
Merchant operations: merchant-scoped SSE, GPS off
Rider idle: no active-trip GPS, carefully designed availability/location strategy
Rider active: authorized GPS upload, delivery events, FCM
Switching modes: close unused subscriptions, invalidate role-specific state
App background: rely on FCM where appropriate; active rider trip tracking may continue only under compliant foreground-service rules

PERFORMANCE TARGETS (initial engineering targets, not guaranteed measurements):
- Smooth UI: 60 FPS target on representative Android devices
- Common screen transitions: <300ms target
- Typical API p95 latency: <500ms for lightweight endpoints under defined test load
- No unbounded memory growth during navigation or mode switching
- No duplicate SSE connections per unnecessary scope
- No GPS upload after tracking should end
- Active-trip GPS upload target: 10-15 seconds, adaptive
- Startup time, APK/AAB size, battery drain and memory usage: baseline first, then establish measurable budgets
- Verify on low- and mid-range real Android devices and emulator

Measure:
flutter analyze
flutter test
flutter build apk --profile (when supported)
Flutter DevTools performance/memory
Android profiler and battery tests
Go unit/integration tests
Database query plans
Load tests for order, payment webhook, dispatch and SSE fanout

Do not report invented benchmark results.

====================
N. SECURITY AND OPERATIONAL SAFETY
====================
- Backend-enforced RBAC and object ownership
- Business_id merchant isolation
- Rider approval and assignment authorization
- Rate limits and abuse protection
- Idempotent payment and delivery commands
- Webhook signature verification
- Unique transaction references
- OTP hashing, expiry and attempt limits
- Secure document storage and access
- TLS, secrets management and redacted logs
- Audit trails and finance reconciliation
- Fraud/anomaly monitoring
- Location privacy and explicit disclosures
- Android location foreground-service and Google Play compliance
- Appropriate rider verification and operational safeguards
- Support and emergency workflows
- Account deletion, retention and data export considerations
- No real-money launch before payment/legal/commercial review

====================
O. PHASE-WISE DELIVERY PLAN
====================
PHASE 0 — READ-ONLY REPOSITORY AUDIT
Inventory screens, routes, APIs, schema, existing commerce features, SSE, authentication and performance baseline.
Deliver architecture diagrams, gap matrix, exact new screen estimate, risk register, implementation roadmap.
STOP for approval.

PHASE 1 — NAVIGATION AND ROLE FOUNDATION
Move Saved into Profile.
Add customer Orders tab.
Define Customer/Merchant/Rider mode switching and permissions.
Preserve existing screens and bookmarks.
Validate routing, RBAC, UI and regressions.
STOP for approval.

PHASE 2 — CUSTOMER COMMERCE
Catalog reuse, cart, address, server pricing, checkout UI, order lifecycle and order history.
Use sandbox or simulated payments initially.
Validate stock, concurrency, order ownership, accessibility and tests.
STOP for approval.

PHASE 3 — MERCHANT ORDER OPERATIONS
Incoming queue, accept/reject, preparation, ready, handover, history, mobile dashboard.
Integrate existing merchant web portal.
Validate business isolation and real-time updates.
STOP for approval.

PHASE 4 — RIDER ONBOARDING AND DELIVERY MVP
Rider registration, admin verification, role access, dashboard, availability, offers, pickup and completion.
Start with manual dispatch and one active job per rider.
Validate atomic assignment, expiry, role revocation and delivery OTP.
STOP for approval.

PHASE 5 — REAL-TIME TRACKING AND NOTIFICATIONS
Rider GPS, foreground service, tracking UI, SSE, FCM, reconnect, stale location and privacy.
Validate on real Android hardware, background/foreground transitions, network outages and battery impact.
STOP for approval.

PHASE 6 — PAYMENT GATEWAY SANDBOX AND SETTLEMENT
Gateway abstraction, sandbox UPI checkout, webhook verification, refunds, ledger and reconciliation.
Do not enable live payments or payouts.
Validate replay, duplicate events, delayed webhook, failure and settlement mismatch.
STOP for approval.

PHASE 7 — AUTOMATED DISPATCH
PostGIS candidate discovery, offer timeout, atomic acceptance, reassignment, operational dashboard.
Validate concurrency, rider availability, location staleness and failure recovery.
STOP for approval.

PHASE 8 — HARDENING, CI/CD AND PILOT READINESS
E2E tests, load tests, security audit, performance profiling, migration review, monitoring, backups, rollback plan and Play release readiness.
Confirm dedicated release/upload signing key.
Deliver production-readiness report and pilot checklist.
STOP for approval before production.

====================
P. VALIDATION GATE FOR EVERY PHASE
====================
For each phase report:
1. Objective and scope
2. Existing code reused
3. New files and changed files
4. Database migrations and rollback approach
5. API contract changes
6. Flutter screens and navigation changes
7. Automated tests executed and exact outcomes
8. Manual emulator/real-device verification, with screenshots where available
9. Security/RBAC checks
10. Performance measurements against baseline
11. Regressions and unresolved issues
12. Explicit pass/fail acceptance criteria
13. Next phase dependencies
14. STOP and request approval

If a validation cannot run, mark BLOCKED/NOT VERIFIED rather than claiming success.

====================
Q. FIRST RESPONSE REQUIRED FROM CODEX
====================
Do not start coding.

Return:
1. Actual repository inventory
2. Existing screen count and route list
3. 29 proposed capabilities classified as reuse/extend/new/defer
4. Current architecture diagram
5. Proposed unified architecture diagram
6. Customer/Merchant/Rider navigation and mode switch diagrams
7. Flutter feature/module structure
8. Go module and API architecture
9. PostgreSQL/PostGIS ER diagram and migration sequence
10. Order/payment/delivery state machine diagrams
11. SSE/FCM/GPS event-flow diagram
12. Payment gateway/settlement architecture and dependencies
13. Performance baseline and measurement plan
14. Phase-by-phase work breakdown with tests, dependencies and acceptance criteria
15. Risks, assumptions, blockers and decisions requiring approval

Finish with:
'PHASE 0 AUDIT COMPLETE — AWAITING APPROVAL TO BEGIN PHASE 1.'

Do not proceed until explicitly instructed.