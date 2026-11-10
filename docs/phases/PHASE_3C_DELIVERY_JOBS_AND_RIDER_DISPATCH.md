# Phase 3C — Delivery Jobs & Rider Dispatch

**Validation date:** 7 November 2026
**Status:** **PASS for isolated QA acceptance**
**Scope:** Delivery job creation, sequential rider offers, rider acceptance, Admin dispatch visibility, Merchant dispatch visibility. No pickup, delivery completion, GPS, payments, or earnings.

## Acceptance result

One QA platform order in Kuanpal was assigned to an approved QA rider. The rider accepted the offer in the Pixel 8 emulator. The same order then appeared assigned to that rider in the Admin Dispatch board and the assigned Merchant's Platform Orders workspace.

| Evidence | Result |
|---|---|
| Customer order | `3d32a461-6d27-4acf-87a1-f1576f542cc8` (`QA-b2162495-0e0e-4773-84e9-f3c2ac41609f`) |
| Delivery job | `a2c2c855-1a5c-4a08-a2c1-b9085b6e8103` |
| Rider | `QA Phase3C Rider`, approved for Kuanpal, Cuttack |
| Offer | Accepted; `delivery_offers.state=accepted` |
| Assignment | Active; `delivery_assignments.state=active` |
| Job | `delivery_jobs.state=assigned` |
| Customer order/payment | `preparing` / `not_collected` |
| Pixel 8 | Offer displayed and accepted in Rider workspace; no GPS was collected |
| Admin Portal | Same order reference, assigned rider, dispatch history visible |
| Merchant Portal | Same order reference, preparing status, dispatch assigned/rider assigned visible |

PostgreSQL readback in the disposable database confirmed the order, active assignment, accepted offer, rider identity, and unpaid status. The append-only delivery event history included offer issuance, acceptance, and rider assignment. Admin and Merchant browser checks authenticated through their OTP login screens and read live APIs; they did not use mocked responses.

## Runtime defects corrected

During runtime verification, rider availability renewal failed on a malformed `EXISTS` expression in `riderCanMaintainAvailabilityDB`. The SQL expression was corrected. A second runtime issue prevented populated offer line items from being scanned because `riderItem` lacked `db` tags for the database column names; tags were added and an integration assertion now verifies populated offer items. The availability heartbeat path and populated offer path are covered by the opt-in PostgreSQL integration test.

The live test order itself contained **zero line items**. Therefore this acceptance verifies assignment and cross-portal visibility, but does not claim that a populated item list was rendered in the rider offer. The integration test separately verifies populated offer item serialization.

## Validation actually executed

- Full backend suite: `cd /mnt/d/grepmind-near/backend && gofmt -w internal/deliverydispatch/service.go internal/deliverydispatch/integration_test.go && go test -count=1 ./...` — **PASS**.
- PostgreSQL-backed dispatch flow against the disposable PostGIS database: `TEST_DATABASE_DSN=<isolated QA DSN> go test -count=1 ./internal/deliverydispatch -run TestDispatchPrepareOfferAcceptAndIsolation` — **PASS**. Covered job creation, sequential offers, acceptance, authorization/isolation, availability heartbeat, and populated offer item scanning.
- Live Admin browser test: `PLAYWRIGHT_BASE_URL=http://localhost:3100 PHASE3C_QA_ADMIN_PHONE=... PHASE3C_QA_ORDER_REFERENCE=... PHASE3C_EXPECT_DISPATCH_STATE=assigned npx playwright test e2e/dispatch.acceptance.live.spec.ts --workers=1` — **PASS**, one test.
- Live Merchant browser test: `PLAYWRIGHT_BASE_URL=http://localhost:3101/ PHASE3C_QA_MERCHANT_PHONE=... PHASE3C_QA_ORDER_REFERENCE=... npx playwright test e2e/dispatch.acceptance.live.spec.ts --workers=1` — **PASS**, one test.
- Pixel 8 acceptance used the Windows-managed emulator (`emulator-5554`) with the isolated API base URL. The rider viewed and accepted the live offer; the subsequent screen showed no remaining offers. Database readback matched the UI action.
- Phase Flutter suite/analyzer and APK build/install were run earlier in this Phase 3C work: **77 Flutter tests passed; analyzer reported 18 non-error diagnostics (3 warnings, 15 infos); APK built, installed, and launched**. These were not rerun after the backend-only fixes in this closeout. No Flutter files changed during the closeout.
- `git diff --check` is part of the closeout and reported no whitespace errors.

Screenshots:

- Pixel 8 offer before acceptance: [phase3c-pixel8-rider-offer-live.png](screenshots/phase3c-pixel8-rider-offer-live.png)
- Pixel 8 after acceptance: [phase3c-pixel8-rider-accepted.png](screenshots/phase3c-pixel8-rider-accepted.png)
- Admin dispatch board: [phase3c-admin-dispatch.png](screenshots/phase3c-admin-dispatch.png)
- Merchant Platform Orders: [phase3c-merchant-dispatch.png](screenshots/phase3c-merchant-dispatch.png)

## Environment and cleanup

The initial restricted command context returned `Wsl/Service/E_ACCESSDENIED`. From the Windows host, the approved elevated direct `wsl` command successfully entered the existing Ubuntu distribution and ran Docker/Go/Playwright commands. This is an execution-context permission distinction, not evidence of a broken WSL/Flutter installation. No SDK, signing, WSL, or persistent Android configuration was changed.

Migrations 001–026 were applied only to the disposable `grepmind_3c_migration_qa` PostgreSQL/PostGIS QA database. Migration 026 remains unapplied to the shared development database. The live API and portals used QA-only credentials and data. The disposable database container and Phase 3C API/Admin/Merchant processes were stopped and removed after evidence capture; no shared development volumes or production services were changed. Temporary OTP screenshots and Playwright traces were removed. No commit was created.

## Boundaries and remaining risks

- Dispatch acceptance applies only to isolated QA; it is not authorization to enable production dispatch.
- The test order was already in `preparing` and had no line items. The platform's order preparation / item handoff should be validated with a populated order before operational rollout.
- The two visible Admin history entries named “rider assigned” required a strict-locator adjustment in the E2E test; dispatch behavior was correct.
- Real rider onboarding remains gated on legal/privacy review, evidence retention/deletion policy, malware scanning, private object-storage authorization, approved migration rollout, and an explicit policy for unpaid orders.
- Pickup verification, handover, customer delivery OTP, delivery completion, GPS, FCM, payments, COD, and earnings are out of scope and remain disabled/unimplemented.

**Recommendation: PASS for Phase 3C isolated-QA scope. Stop here; Phase 3D requires separate approval.**
