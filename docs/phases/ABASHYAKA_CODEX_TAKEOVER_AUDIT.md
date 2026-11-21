# Abashyaka Codex takeover audit

**Audit date:** 20 November 2026  
**Overall status:** PARTIAL

Source inspection confirmed why merchant-owned orders cannot display Customer delivery verification codes. It also confirmed that the shared Nginx configuration targets the isolated QA API and that debug builds enable QA OTP challenge instrumentation by default. Live routing, installed APK identity, and authenticated acceptance remain unverified.

## Repository and existing work

- **VERIFIED** — `D:\grepmind-near` was on `abashyaka-dev-01` at `8d5eb0fec1e10417073c01419201ac1859c3e78c`, with no configured upstream and no staged, unstaged, or untracked files at audit time.
- **VERIFIED** — Antigravity's handoff is committed at `e9aa875`. The subsequent commit combines the Orders redesign with authentication, Nginx, API, and Admin Web changes.
- **VERIFIED** — The audit reviewed the root instructions and README, phase index and acceptance reports, migration inventory, QA scripts, and the `design-reference` and `ref-image` directories. The approved Abashyaka palette and launcher mark are documented in the [design guidelines](../../design-reference/abashyaka/DESIGN_GUIDELINES.md).

## Development environment

| Status | Finding |
|---|---|
| VERIFIED | Windows resolves ADB at `D:\emulator\android-sdk\platform-tools\adb.exe`. SDK platform tools, emulator tooling, build tools, and system images are present. |
| BLOCKED | `adb devices -l` failed to start or connect to the daemon. Port 5037 was unreachable, so live AVD mapping, installed build identity, and role sessions remain unverified. |
| PARTIAL | Windows resolves `wsl.exe`. Flutter, Dart, Go, and Docker did not resolve in the audit's Windows shell. The repository requires interactive host PowerShell for WSL checks. Ubuntu tool versions and Docker runtime remain unverified. |
| VERIFIED | [Android Gradle](../../apps/mobile/android/app/build.gradle.kts) declares `local.grepmind.grepmind_mobile` and currently uses debug signing for release. The emulator URL defaults to `http://10.0.2.2:80` with the build-time `API_BASE_URL` override. |
| VERIFIED | The existing local `app-debug.apk` has SHA-256 `91AF7143D90FBC659915D74A10AA8A0E7B9431D1BFA7213B97E1733D7712ECEE`. Its source revision and installed identity remain unverified. |

The handover and Phase 02I report list Customer `5554`, Merchant `5556`, and Rider `5558`. The supplied repository instructions list Customer `5560`, Merchant `5558`, and Rider `5556`. Resolve actual serials by AVD name before installation or login: `Pixel_8`, `Pixel_8_Merchant_QA`, and `Pixel_8_Rider_QA`. Admin acceptance uses a browser.

## Architecture and commerce

| Status | Finding |
|---|---|
| VERIFIED | Flutter Android uses Material 3, Riverpod, and Dio across Customer, Merchant, and Rider workspaces. The Go modular monolith uses PostgreSQL/PostGIS and MinIO. Docker Compose and Nginx support the API and the Next.js portals. OTP, JWT sessions with refresh, RBAC, SSE, and the existing payment and delivery workflows are part of the stack. |
| VERIFIED | The premium Orders hub uses platform catalog and locality queries, `PlatformCatalogScreen`, `PlatformCartScreen`, and `platformCartProvider`, with separate Food and Grocery scopes. Platform checkout quotes and submits through `/platform/orders`. |
| VERIFIED | Merchant storefronts use a business-scoped cart and quote/order endpoints. `CheckoutReviewScreen` is an existing storefront checkout entry point. Both commerce paths share `customer_orders` and use `order_source` to identify the path. |
| VERIFIED | There are 43 numbered migrations through [043](../../backend/migrations/043_merchant_owned_commerce_unification.sql). It adds merchant grocery attributes and extends delivery job creation to merchant-catalog orders. Applied status in shared development and production is unverified. |
| PARTIAL | Merchant product alignment needs a source-backed query for merchant identity, price, stock, and selected-locality eligibility, plus quote-time validation and single-merchant cart enforcement. Preserve the approved visuals and platform order history. Commerce routing requires approval. |

Migration 043 falls back to the earliest active delivery locality when a merchant order lacks one. Verify address-to-dispatch locality consistency before expanding beyond the pilot.

## Phase completion matrix

| Phase | Classification | Evidence |
|---|---|---|
| Abashyaka 01A–01F.1 | REPORTED ONLY | Branding, Customer navigation, discovery, and Doctor/Transport corrections are documented. Current Android behavior is unverified. |
| 02A–02D | REPORTED ONLY | Merchant onboarding, dashboard, orders pipeline, and catalog have scoped acceptance records. |
| 02E | REPORTED ONLY | Isolated Food COD and sandbox UPI are reported. Test counts describe different scopes. |
| 02F | VERIFIED | The architecture audit exists and describes the source at its review date. |
| 02G–02H | REPORTED ONLY | Merchant-owned commerce reportedly passed isolated multi-emulator QA. |
| 02I | PARTIAL | Grocery `GN-BA2EE85A` and Food `GN-42904B10` reportedly completed in isolated QA. The handover reports API-assisted Customer verification. Current source confirms the merchant Customer UI cannot expose the code. |
| Premium Orders redesign | VERIFIED | Source is committed and still uses platform providers. Current visual acceptance is unverified. |
| Abashyaka 03A–03C | REPORTED ONLY | Rider workspace, handover, and map hubs have isolated-QA reports. Upcoming Rider modernization is a separate gate. |
| Historical delivery, payment, and finance | REPORTED ONLY | The [phase index](README.md) records isolated passes, partial gates, and deferred work. These results do not confer production acceptance. |
| 02I.1, 02I.2, final 02I, modernization and pilot | BLOCKED | Implementation authorization was outside the read-only audit scope. |

## Customer tracking

- **VERIFIED** — [OrderTrackingScreen](../../apps/mobile/lib/core/screens/order_tracking_screen.dart) returns early from `_loadDispatchStatus()` for sources other than `platform_catalog`. It also renders the live timeline and verification button only for platform deliveries, and the button requires `execution_state == 'en_route'`. Merchant orders therefore skip the status request and cannot render the button.
- **VERIFIED** — `OrdersTabNavigator` opens the shopping hub. My Orders opens history, which passes the order ID to tracking. [CustomerOrdersNotifier](../../apps/mobile/lib/core/providers/customer_orders_provider.dart) reads `/customer/orders`. The [backend listing](../../backend/internal/operations/service.go) filters by customer ownership and does not restrict order source. `CustomerOrder` parses `order_source`.
- **VERIFIED** — The [delivery verification handler](../../backend/internal/deliverydispatch/execution.go) supports eligible orders from both sources. It enforces ownership, requires the rider to be en route, applies a cooldown, and stores a keyed hash.
- **PARTIAL** — A fresh authenticated replay is required to establish whether the earlier run also had a history refresh, APK mismatch, or checkout navigation problem. Prove that a new merchant order appears in My Orders, opens tracking, and exposes the verification action at the correct stage.

## Authentication and QA isolation

| Classification | Finding |
|---|---|
| SECURITY RISK | [app_provider.dart](../../apps/mobile/lib/core/providers/app_provider.dart) defaults `QA_OTP_AUTOMATION` to true. The `kDebugMode` path emits challenge metadata. Server verification remains in place. Ordinary debug builds should require explicit opt-in to emit the metadata. |
| SECURITY RISK | The Phase 02I report contains plaintext QA handover codes. Future evidence must redact them. Review the tracked report and QA output handling during the approved correction. |
| SECURITY RISK | [Shared Nginx](../../infrastructure/docker/nginx/nginx.conf) changed the default host's `/api/` and `/` upstream from `api:8080` to `grepmind_4c_qa_api:8080`. The parent commit and [Compose](../../docker-compose.yml) identify the original shared API. Some named hosts still use the shared API, so requests can reach different backends by hostname if this file is loaded. |
| PARTIAL | The [QA startup script](../../scripts/qa/phase4c-e2e-start.sh) defines separate loopback QA services, and the repo has a dedicated QA proxy config. Active Nginx config, Docker network membership, database targets, and manual network attachments remain unverified. |

## Tests and validation gaps

- **VERIFIED** — Git tracks 44 Flutter test files, 8 Flutter integration-test files, 41 Go test files, 17 Admin Playwright specs, and 6 Merchant Playwright specs. These are file counts.
- **VERIFIED** — Existing coverage includes history navigation, live tracking, and backend code issuance. The QA inventory includes full-commerce and multi-role runners, isolated stack scripts, and protected OTP UI wrappers.
- **REPORTED ONLY** — Phase 02A reported 150 Flutter cases, Phase 02E reported a 58-case grouped run, and Phase 02I cited 35+ core cases and dedicated integrity checks. Historical analyzer records include 18 diagnostics and a later seven-info result. Current totals and analyzer baseline remain unknown.
- **BLOCKED** — No tests or analyzer runs were executed in this read-only audit. Full Flutter and Go/PostGIS suites, web tests, and authenticated multi-role UI acceptance remain pending.

## Recommended implementation sequence

| Gate | Work and likely files |
|---|---|
| 02I.1 | Update `order_tracking_screen.dart` and focused regression tests using existing endpoints. Verify merchant and platform deliveries, ineligible states, and an unrelated customer. Inspect `order_history_screen.dart`, `customer_orders_provider.dart`, `customer_order.dart`, and checkout confirmation navigation if replay identifies a separate gap. |
| 02I.2 | Approve catalog and cart routing before updating `order_shopping_hub_screen.dart` and the selected repositories/providers. Require explicit debug QA opt-in in `app_provider.dart` and QA wrappers, and review result redaction. Inspect live routing and networks before approving any shared `nginx.conf` change. |
| Final 02I | Capture fresh analyzer and suite results. Install one hashed APK on the three verified role AVDs. Complete fresh Food and Grocery orders across Customer, Merchant and Rider Android, Merchant Web where relevant, Admin Web, and API/PostgreSQL reconciliation. Redact codes and credentials from the evidence. |
| 03 through 06 | Review 02I closure before Rider modernization, Admin modernization, production readiness, and the Kuanpal pilot. |

The audit made no application, database, authentication, or infrastructure changes.
