# Phase 5C — Admin finance overview

**Status — PASS for isolated Admin Web read-only acceptance (16 November 2026).**

## Scope

The Admin portal has a read-only Finance overview in its sidebar. It shows the refund queue filtered by server status, posted Merchant payables with their payment source, COD remittances, and Merchant settlement simulations. Each section displays up to ten records and handles loading, empty, denied, unavailable, and other error responses independently. The COD and settlement sections link to their existing detail views.

The overview calls the existing Admin GET endpoints. The backend continues to enforce the existing finance read permissions and environment settings. The overview does not post journals, change refund state, or execute payouts. A general payment-attempt list is outside this slice because the API has no Admin-wide payment-attempt listing endpoint.

## Acceptance

The isolated QA browser accepted a synthetic Admin through the existing scoped OTP flow, returned HTTP 403 for the refund queue when the Admin lacked `finance.read`, and displayed the permission error in the Refunds section. Populated overview scenarios are exercised with intercepted API responses. Authenticated populated acceptance and same-record PostgreSQL reconciliation remain open.

The Admin production build, TypeScript check, targeted ESLint, and populated browser test passed. The live permission-denial test passed on its first run. A repeat was rate-limited at OTP request and was stopped without changing QA settings.

### 16 November 2026 acceptance recheck

**PARTIAL.** The running isolated QA stack has two active Admin records: the protected root and the synthetic dashboard account. It has zero active finance grants and no grant requests. The historical Phase 4D QA reviewer and operator are absent as authorized Admins in this runtime. The dashboard account cannot request or approve its own `finance.read` grant. Live acceptance requires two distinct existing QA Admins authorized for `finance.configure`, separate from the target.

The finance access and Merchant finance Go suites passed against a separate tmpfs PostGIS database initialized with migrations 001–037. The finance access integration test verified independent approval, requester self-approval denial, and decision replay denial. The populated dashboard browser test passed with intercepted responses after correcting the test's Admin trends payload. No roles, grants, feature flags, or financial records were changed in the running QA stack. Authenticated populated acceptance and reconciliation remain pending.

### Disposable synthetic approver acceptance

The live read-permission gate passed on 16 November 2026. A dedicated tmpfs PostGIS database received migrations 001–041. Its API and protected OTP inbox used a separate Docker network and loopback bindings. The synthetic requester and independent approver held only the finance configuration permission needed to use the grant workflow. The dashboard Admin received only `finance.read`.

The live Playwright test signed in through the Admin browser with scoped OTP. All four overview requests returned 403 before approval. The grant request returned 201, self-approval returned 403, independent approval returned 200, and decision replay returned 409. Refreshing the same Admin browser returned 200 and rendered the empty state in all four sections. PostgreSQL confirmed the single approved read grant, the two grant audit events, and zero refunds, remittances, payables, batches, and journals. Live financial flags remained disabled.

The disposable services, network, proxy, and private OTP runner configuration were removed. The existing QA portal remained available. Populated same-record browser, API, and PostgreSQL reconciliation remains pending.

### Populated acceptance — PASS for isolated Admin Web scope

On 16 November 2026 a fresh Phase 5C tmpfs PostgreSQL stack applied migrations 001–041. The existing OTP reader authenticated synthetic actors. Two independent synthetic Admins granted the dashboard Admin only `finance.read` through the normal request and approval endpoints. Business, catalog, rider, and governance prerequisites were bootstrapped in the disposable database. Normal application APIs generated all four financial records using sandbox UPI, synthetic COD, and simulated settlement. The browser test used live HTTP responses and read-only PostgreSQL queries.

| Panel | Order reference | Record ID | Server amount | Server state or source |
| --- | --- | --- | --- | --- |
| Refunds | `GN-9751CD7E` | `9e536784-acbf-4250-8e0c-2f7035eca819` | ₹90.00 | Requested |
| COD remittances | `GN-70800236` | `d064f00c-8111-4e47-88d0-2c11fcda02c9` | ₹280.00 | Verified |
| Posted merchant payables | `GN-70800236` | `a46f6858-0858-483c-95e3-bfd73965571f` | ₹199.50 | Synthetic COD collection |
| Merchant settlement simulations | `GN-70800236` | `f4838988-5250-456a-8a04-e18526e6a71a` | ₹199.50 | Reconciled |

The Playwright populated test passed. All four Admin requests returned HTTP 200. Each response matched its PostgreSQL record by ID, amount, currency, and the state or payment source shown in the browser. The COD collection, remittance, payable and batch item were linked in PostgreSQL. Capture, COD collection, COD remittance, payable accrual, and settlement simulation journals each balanced to zero signed paise. The requested refund remained in its queue. Payout transfers counted zero, and live financial flags stayed disabled.

[Populated Admin Finance Overview screenshot](evidence/phase5c/finance-overview-populated.png).

This gate covers the Admin Web read-only dashboard. The underlying commerce events were exercised through the isolated API. No Android APK was built and no Android or Merchant Web acceptance was claimed for those underlying workflows. The previous read-permission gate remains recorded above.
