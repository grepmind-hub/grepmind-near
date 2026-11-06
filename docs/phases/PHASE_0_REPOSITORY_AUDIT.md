# Phase 0 — Repository audit

**Audit date:** 5 November 2026
**Scope:** Read-only repository, architecture, feature, security, and launch-readiness audit.
**Implementation status:** No application source or migration changes were part of the Phase 0 audit.

## Purpose

Establish a source-backed baseline for the Flutter customer/merchant app, Go modular monolith, PostgreSQL/PostGIS schema, merchant and admin portals, Docker Compose, and current launch risks. Changelog and UI inventory claims were checked against code and tests; a documented screen was not treated as proof of a working end-to-end feature.

## Audit records

The detailed findings remain in the project-audit set:

- [Current application status](../project-audit/CURRENT_APPLICATION_STATUS.md)
- [Feature gap analysis](../project-audit/FEATURE_GAP_ANALYSIS.md)
- [Cross-platform acceptance matrix](../project-audit/CROSS_PLATFORM_ACCEPTANCE_MATRIX.md)
- [Audit test results](../project-audit/AUDIT_TEST_RESULTS.md)
- [Next phase roadmap](../project-audit/NEXT_PHASE_ROADMAP.md)
- [Merchant billing specification](../project-audit/MERCHANT_BILLING_SPECIFICATION.md)
- [Google Play launch checklist](../project-audit/GOOGLE_PLAY_LAUNCH_CHECKLIST.md)

## Baseline conclusions

- The repository is a modular monolith with Flutter, Go/chi, PostgreSQL/PostGIS, Next.js portals, Nginx, MinIO, SSE, and Docker Compose. No architectural rewrite was recommended.
- Core discovery, authentication, merchant catalog, service requests/availability, and hospitality order/reservation paths exist in source. Completeness varies by flow and acceptance evidence; the audit matrix records specific limits.
- Operational booking data uses `customer_orders` and `customer_order_items`; later phases must extend these workflows rather than create an incompatible customer order system.
- The migrations present at audit time had no repository migration ledger/upgrade runner. SQL mounted into a new PostgreSQL data directory does not upgrade an existing volume.
- A repository-managed backup, restore automation, and restore drill were not found. A persistent Docker volume is not a backup.
- Several web browser checks were blocked by missing Playwright browser/runtime dependencies or credentials. Those failures were recorded as blocked, not application passes.
- Local development records, test-fixture accounts, and UI showcase claims are not evidence of production activity or readiness.

## How to use this record

Findings are historical. Revalidate them against current source, runtime, tests, and database before implementation. Phase 1 work completed afterward and changed the navigation/role baseline. Phase 0 did not approve production deployment, real payments, real SMS, or destructive database actions.
