# Phase 2R.1 — Platform Catalog Foundation

**Status:** PASS — backend, database, Admin production build, and browser acceptance completed; awaiting explicit approval for Phase 2R.2
**Date:** 6 November 2026
**Branch:** `development-02`

## Goal and boundaries

This phase establishes the Grepmind-owned Food and Grocery catalog and explicit partner-to-variant fulfillment mappings. It is a separate domain from merchant-owned discovery products. It does not change the Phase 2B/2C/2D customer cart, checkout, or `customer_orders` workflows. No products are seeded. Customer Flutter screens, payment collection, dispatch, and rider GPS remain out of scope.

## Implemented design

- Additive migration `021_platform_catalog.sql` defines vertical-specific categories, platform products, variants with INR prices in integer minor units and price revisions, product city/locality availability, partner coverage, and explicit partner product-variant mappings.
- Public catalog APIs filter to active products, active categories/variants and Cuttack/Jajpur availability. Search and pagination are bounded. Public responses do not include partner supply costs.
- Admin-only APIs create/update/deactivate catalog data, variants, mappings, and partner coverage. Mutations run with audit-log inserts in the same transaction. System Food/Grocery roots cannot be deactivated.
- Mapping approvals require an approved, verified business, active product/category/variant, and intersecting product and partner coverage. A mapping remains pending until an administrator approves it.
- Merchant capability inspection requires ownership or active membership in the requested `business_id`; returned data excludes supply price.
- Admin portal adds a Platform Catalog workspace for products, categories, variants, partner mappings, inventory/cost updates, coverage controls, and image uploads through the existing media endpoint. It reads live API data and displays loading/error states.
- `api/openapi.yaml` documents public browsing, Admin management and merchant capability routes.

## Routes added

- Public: `GET /api/v1/catalog/categories`, `GET /api/v1/catalog/products`, `GET /api/v1/catalog/products/{id}`.
- Admin: category list/create/update; product list/create/read/update/soft-deactivate; variant create/update; partner mapping list/create/update; partner coverage list/create/soft-deactivate under `/api/v1/admin/catalog/...`.
- Merchant: `GET /api/v1/merchant/businesses/{id}/catalog-capabilities`.

All Admin routes use existing `requireAdmin` authentication. Merchant capability uses existing authenticated identity and service-side membership checks. No existing public or merchant product route was replaced.

## Validation status

| Check | Result |
|---|---|
| Admin portal `npm run typecheck` | Passed after final UI and E2E edits |
| Targeted Admin ESLint | Passed with 0 errors and no diagnostics on the changed Admin layout, catalog view, or E2E spec |
| Admin production Docker build | Passed using `docker build --build-arg NEXT_PUBLIC_MERCHANT_PORTAL_URL=http://localhost:3001/ -t grepmind-admin-phase2r1-qa .` from `apps/admin-web`; no Google Fonts access was required |
| Admin Playwright suite | Passed 4/4 tests against isolated Admin/API containers: OTP login screen, unauthenticated dashboard redirect, authenticated Admin workspace and sign-out, and full platform catalog workflow |
| Admin browser catalog workflow | Passed: unauthenticated catalog request returned 401; Food and Grocery products created; Food description and selling price edited; activation/deactivation tested; search filter tested; eligible Jajpur partner coverage and finite-stock mapping configured and approved; Admin displayed private partner cost |
| Merchant price isolation | Passed in Go API integration test: merchant attempt to change a platform variant selling price returned 403 |
| QA data cleanup | Passed: the cloned local database and temporary Admin/API/Nginx containers and images were removed after testing; the original local database was not migrated or modified |
| `gofmt` on changed Go files | Passed in WSL |
| `go test -count=1 ./...` | Passed in WSL |
| Database-backed API/session authorization tests | Passed in a disposable PostGIS-backed clone. `TestOwnershipAndTenantRoutes`, `TestAdminUserAccessRoleBoundaries`, and auth/session integration tests passed |
| Migration 021 execution | Passed in a disposable clone of the local database; verified Food and Grocery roots. The clone was dropped after browser validation |
| Public catalog API and image URL behavior | Passed: empty, omitted, JSON-null, single, and multiple image URL cases return correct arrays; active catalog listing filters by city and does not expose partner supply costs |
| OpenAPI YAML syntax | Passed using the installed PyYAML parser; dedicated OpenAPI semantic validation was unavailable |
| Targeted `git diff --check` | Passed with `core.whitespace=cr-at-eol` to recognize the repository's CRLF `AGENTS.md`; Git emitted normal LF-to-CRLF warnings for touched files |

The normal sandboxed Windows command runner can still report `Wsl/Service/E_ACCESSDENIED`; the same WSL commands succeeded through the approved elevated execution path. This is a runner access boundary, not a WSL startup failure. The initial database-backed API test exposed a PostgreSQL `text[]` scan mismatch for product image URLs; the query now serializes the array as JSON before scanning. The Admin production build initially required Google Fonts because of `next/font/google`; the layout now uses the existing system font fallback declared in the stylesheet, preserving the visual direction without a build-time font download.

The API integration tests verified authorization, tenant isolation, partner mapping approval, and transactional audit persistence. Admin catalog mutations now refresh data in the background so the coverage selection remains mounted after save instead of clearing the user's selection.

## Compatibility and known limitations

- Existing merchant-owned `products`, `customer_orders`, cart, checkout, reservations, hotel bookings, service requests, and Phase 2D tracking remain in place.
- There are no platform products until Admin enters real product data.
- Partner selection and order creation against platform products are future work; this phase only records approved capabilities and coverage.
- Admin image URL validation and API serialization were tested. Uploading a binary image through the Admin UI and confirming MinIO retrieval remain unverified.
- The existing development database was not changed. Migration 021 and all QA products/mappings existed only in a temporary cloned database that was dropped.

## Browser evidence

![Admin Food and Grocery catalog](../../apps/admin-web/test-results/phase2r1-admin-catalog.png)

![Approved partner mapping and coverage](../../apps/admin-web/test-results/phase2r1-admin-partner-mapping.png)

## Acceptance recommendation

**PASS for Phase 2R.1.** Backend, database-backed authorization, migration, catalog image regression, Admin typecheck/lint, production Docker build, and authenticated Playwright browser workflows passed. No catalog QA data remains in the local development database. Phase 2R.2 has not started; wait for explicit product-owner approval before proceeding.
