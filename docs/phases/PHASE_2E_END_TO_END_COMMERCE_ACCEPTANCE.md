# Phase 2E — End-to-End Commerce Integration & Acceptance

**Final device acceptance:** 7 November 2026  
**Status:** **PASS**  
**Scope:** Cross-platform acceptance of one isolated QA customer order, merchant fulfillment, and customer tracking refresh.

## Acceptance result

The Pixel 8 displayed the same platform order before and after the assigned partner changed it to ready for pickup in the live Merchant Portal. Returning to the open exact-order details and tapping its refresh control showed the complete ordered status history, matching both the customer-authenticated API and PostgreSQL.

| Check | Result | Evidence |
|---|---|---|
| Customer platform checkout | PASS | One order created through the Pixel 8 UI in the disposable QA environment. Reference `GN-DCE70C14`; UUID `dce70c14-7da8-480a-9161-d73aa0563b59`. |
| Merchant fulfillment | PASS | Authenticated live Merchant Portal actions: `placed → accepted → preparing → ready_for_pickup`. The portal showed one order in Ready for pickup. |
| Same-order Pixel 8 tracking | PASS | Pixel 8 showed the same reference and status history: Order placed, Accepted by partner, Preparing, Ready for pickup. After tapping refresh on that exact detail screen, the same status and timeline remained visible. |
| Customer API and order history | PASS | `scripts/qa/phase2e-verify-customer-order.mjs` authenticated the QA customer, fetched `GET /api/v1/orders/{id}` and customer order history, then asserted the exact ID and status sequence. It printed no OTP or token. |
| PostgreSQL state | PASS | The isolated database recorded `ready_for_pickup`, `not_collected`, and four append-only events in order. |
| Payment and delivery claims | PASS | Payment remained `not_collected`. No rider assignment or ETA was present; the app stated that delivery estimate and live location were unavailable. |
| QA cleanup | PASS | Removed all five isolated containers, `grepmind-phase2e-qa-net`, and the two QA-only API/Merchant images. Shared Grepmind containers remained running and healthy. |

## Order evidence

- **Order ID:** `dce70c14-7da8-480a-9161-d73aa0563b59`
- **Reference:** `GN-DCE70C14`
- **Locality:** Kuanpal, Cuttack
- **QA product:** Phase 2E QA Chicken Biryani, quantity 1
- **Partner:** Phase 2E Final QA Food Partner Kuanpal
- **Final status:** `ready_for_pickup`
- **Payment status:** `not_collected`
- **PostgreSQL event history (UTC):** `placed` at `2026-11-06 20:40:24.871103`; `accepted` at `20:53:48.788832`; `preparing` at `20:53:54.488967`; `ready_for_pickup` at `20:53:59.675084`.

The Pixel 8 evidence screenshot is [phase2e-final-pixel8-ready-for-pickup.jpg](screenshots/phase2e-final-pixel8-ready-for-pickup.jpg). It shows the same order reference, current status, four timeline entries, and no rider ETA or live location.

## Runtime setup and discrepancy resolved

The fresh acceptance run used a disposable PostGIS database initialized from schema only, migrations through 024, a QA API, Nginx, MinIO, and a Merchant Portal container on a dedicated Docker network. No rows or volumes were copied from the shared development database. Migrations 023 and 024 remain unapplied to the shared database.

The first isolated Merchant Portal container was an older image and did not include the Platform Orders screen. The current repository source was built as a separate QA-only image and substituted only in the isolated environment. After reload, the authenticated live portal exposed Platform Orders, showed the assigned order, and accepted each transition. The customer order transition itself was submitted through the portal UI, not a script or mocked API.

## Commands and checks

Commands executed in this final acceptance run:

- `wsl -e bash -lc 'cd /mnt/d/grepmind-near && docker build --build-arg API_PROXY_TARGET=http://grepmind-phase2e-qa-nginx/api/v1 -t grepmind-near-merchant-web:phase2e-final-qa ./apps/merchant-web'` — **PASS**, Next.js production build completed. Docker emitted five existing legacy `ENV` syntax warnings from the Dockerfile.
- `wsl -e bash -lc 'cd /mnt/d/grepmind-near && node scripts/qa/phase2e-verify-customer-order.mjs dce70c14-7da8-480a-9161-d73aa0563b59'` — **PASS**, exact customer-owned order and history, ordered status list, and unpaid state verified.
- Read-only PostgreSQL queries against `grepmind_phase2e_qa` — **PASS**, final order/payment status and four event rows matched API/UI.
- Pixel 8 UI — **PASS**, opened exact order details, observed full status timeline, tapped refresh, and observed the same current status and event history.
- `docker rm -f` for the five named QA containers, `docker network rm grepmind-phase2e-qa-net`, and removal of the two QA-only images — **PASS**.
- Post-cleanup `docker ps` — **PASS**, shared `grepmind_api`, Merchant Portal, Admin Portal, worker, Nginx, MinIO and PostgreSQL remained running; QA containers/network/images were absent.

Earlier Phase 2E work recorded in the previous report remains applicable: Go suite passed against isolated PostgreSQL; Flutter tests passed (73); Admin and Merchant typecheck/build passed; OpenAPI parsed as 3.0.3 with 109 paths; Flutter analysis reported 18 existing diagnostics (3 warnings, 15 infos, no errors; exit code 1); ownership, isolation, rejection, idempotency, stock and concurrency tests passed. These suites were not rerun during this narrow final device check.

## Cleanup and environment boundary

All records lived in the disposable QA database and were removed with its containers. The shared development database and production were not modified. Migrations 023 and 024 are still not applied to the shared development database; isolated acceptance does not establish shared-environment deployment readiness.

## Limitations

- This run verifies a manual order-detail refresh, not SSE delivery or FCM push behavior.
- The analyzer retains the previously recorded 18 diagnostics; this acceptance-only run did not rerun or change the analyzer baseline.
- No rider assignment, live GPS, delivery ETA, or customer payment was implemented or asserted.

**Phase 2E final recommendation: PASS.** The remaining same-order Pixel 8 timeline acceptance check is complete. Stop here; later rider, payment, GPS, or other development requires separate approval.
