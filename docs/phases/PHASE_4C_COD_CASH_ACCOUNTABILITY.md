# Phase 4C — Synthetic COD, Rider Cash Accountability & Remittance Reconciliation

**Date:** 11 November 2026  
**Status:** PASS for isolated QA — authenticated same-order customer, merchant, rider, and finance acceptance completed.  
**Scope:** Isolated QA only. Migration 034 was not applied to shared development or production.

## Goal and safety boundary

Phase 4C adds a synthetic QA workflow for cash-on-delivery accounting. It does not authorize physical cash collection, live payment collection, COD operations, merchant settlements, refunds, payouts, or production deployment. The app labels the flow synthetic. Effective COD configuration requires QA/test environment and explicit database feature flags; local and production environments fail closed.

COD collection is a rider liability to the platform collection process. It is not rider earnings, merchant revenue, or merchant settlement. The legacy `customer_orders.payment_status` stays `not_collected`; collection and remittance state are separate projections. Historical orders are not backfilled.

## Implementation

- Added additive migration `backend/migrations/034_cod_cash_accountability.sql` for frozen COD obligations, collection records, rider remittance claims, audit events, and QA-only feature controls. Immutable order amount/currency snapshots are in integer minor units. The obligation can move only from `due` to `collected`, and only after its immutable collection record exists.
- Added `backend/internal/codcash/` services for order COD status, rider cash summary and remittance history/submission, Admin collection/remittance/audit/reconciliation views, and finance-authorized remittance review. Remittance creation is idempotent, limited to outstanding rider liability, and does not reduce liability until an independent finance reviewer verifies it and posts a balanced journal.
- Connected platform checkout to explicit `upi` or `cash_on_delivery` choice when server eligibility allows it. The server freezes the authoritative order total. COD orders cannot create UPI intents, and payment method cannot be changed after order submission.
- Connected delivery completion to the existing customer OTP transaction. A COD order requires explicit synthetic collection confirmation from its assigned rider; collection, balanced ledger posting, and delivery completion commit atomically. No order is marked paid.
- Added a read-only customer payment card for COD status, a Rider cash accountability/remittance screen, a read-only Merchant order indicator, and an Admin COD Finance area for reconciliation and remittance review.
- Updated `api/openapi.yaml` and API route wiring for the COD status, rider cash/remittance, Admin finance/review/audit/reconciliation, checkout, and COD handover contracts.

## Controls and invariants

- No client-supplied amount is trusted for the order obligation or COD collection.
- Rider endpoints are scoped to the authenticated rider; the assigned rider is established by the delivery assignment.
- Customer order status is ownership-protected. Finance review requires the appropriate authorization and prevents rider self-review.
- Repeated remittance requests use idempotency keys and payload fingerprints; changed payload reuse conflicts. Concurrent same-key requests return the same record.
- A remittance cannot exceed unverified outstanding liability. Liability only decreases after authorized verification and ledger posting.
- Journals use INR minor units and the existing balanced append-only financial ledger. COD liability postings are distinct from rider earnings and UPI capture.
- COD feature switches remain fail-closed outside QA/test. No migration or QA records are written to shared development/production.

## Validation performed

| Check | Result |
|---|---|
| `bash scripts/qa/phase4c_cod_cash_accountability.sh` through Windows-host WSL terminal | PASS; applied migrations 001–034 to disposable tmpfs PostGIS, full Go suite and `internal/codcash` DB acceptance passed; disposable container removed |
| COD PostgreSQL integration | PASS; balanced single collection journal, unchanged `not_collected`, ownership denial, duplicate collection rejection, concurrent idempotent remittance, excess liability rejection, finance authorization, verified remittance journal and liability reconciliation |
| `flutter test --no-pub` | PASS; 100 tests |
| Focused analysis of changed Dart files | PASS; no issues found |
| Full `flutter analyze --no-pub` | INCOMPLETE; command did not finish and was interrupted. Do not infer a pass or diagnostic count |
| `flutter build apk --debug --no-pub` | PASS |
| APK installation and launch | PASS on `emulator-5554` and `emulator-5556`; both received SHA-256 `cb74d755097fe0cd82e2f71517f843f994c368d853a6944acea10c74bf35d288` |
| Emulator COD workflow | NOT VERIFIED. The installed APKs use the shared local API, whose schema remains through migration 033; no customer sign-in or COD checkout was attempted against it |
| Admin typecheck and production build | PASS |
| Merchant typecheck and production build | PASS |
| OpenAPI YAML parse | PASS |
| `git diff --check` on changed source scopes | PASS (Git reported expected LF/CRLF warnings) |

The emulator evidence is launch-only, not authenticated workflow acceptance. Screenshots are `docs/phases/evidence/phase4c_emulator_5554_login.png` and `docs/phases/evidence/phase4c_emulator_5556_login.png`; they show the login screen and contain no personal data. The first attempt to invoke `wsl` from the current automation process returned `Wsl/Service/E_ACCESSDENIED`; an already-open Ubuntu WSL terminal launched from the Windows host remained available and was used for build and validation. This is an execution-context limitation, not evidence of a repository WSL defect.

## Earlier targeted E2E acceptance recovery attempt (superseded 11 November 2026)

- Started a fresh disposable PostGIS stack using `scripts/qa/phase3e-start-isolated.sh`; migrations 001–034 were applied to its tmpfs database. Built the current API image and ran it separately on host port 18083 with `APP_ENV=qa`, `SANDBOX_COD_ENABLED=true`, and the QA database. A separate tmpfs MinIO was attached. Synthetic COD and financial-posting switches were enabled only in that disposable database; UPI, real COD, settlement and real-money flags remained false.
- Built an APK with `flutter build apk --debug --no-pub --dart-define=API_BASE_URL=http://10.0.2.2:18083`. SHA-256: `04bc9a263935a83cee27573b03cdf5b43e8bc1a847735013e7c80cf59ca3eb52`. Installed on `emulator-5554` and `emulator-5556`, cleared app data, and launched both.
- The authenticated journey stopped at customer OTP. The QA API correctly omitted OTP from its response, but `OTP_PROVIDER=stub` has no delivery adapter in `APP_ENV=qa`; the phone UI reported it could not send a code. No OTP disclosure, auth bypass, shared API use, customer order, COD collection, or remittance was attempted/created. The same-order Customer/Merchant/Rider/Finance flow was not validated.
- Cleanup removed the exact QA API, QA MinIO, tmpfs database, isolated network and QA image; cleared the Grepmind app data on both emulators; and confirmed no `grepmind_4c_qa_*` or `grepmind_3e_qa_*` containers remained. Shared Grepmind API, PostgreSQL, MinIO, Nginx, Admin, Merchant and worker containers remained running and were not modified. Temporary screenshots containing QA login details were deleted.
- This is a **blocked acceptance attempt**, not a product-code failure and not a COD UI PASS. Database/API isolation worked. The remaining prerequisite is a disposable QA OTP delivery/capture mechanism that does not disclose OTPs in API responses, or an operator-provided QA OTP delivery service. Do not weaken local/production OTP disclosure rules to close this gate.

## Previously pending acceptance gate (closed below)

This gate was completed in the final acceptance run below. The text here records the pre-acceptance requirement only.

The full Flutter analyzer was rerun for final closeout; see results below. The missing standalone Admin finance dashboard beyond the COD controls remains tracked separately.

## Phase 4C-E2E-R follow-up — secure QA OTP and earlier device retry (11 November 2026)

- Added `backend/internal/auth/qa_otp_file.go`, selected only when `APP_ENV=qa`, `QA_OTP_DELIVERY_ENABLED=true`, and `OTP_PROVIDER=qa_file` are all explicit. The provider accepts only exact configured E.164 allowlist entries and writes a short-lived code/expiry record into a private directory. The isolated API mounts that directory as mode-0700 tmpfs; it is not exposed through an HTTP route, API response, SSE, or logs. The QA runner reads and deletes one code through `docker exec`; no fixed OTP or verification bypass was added.
- Added configuration/provider security tests and `TestOTPExpiryAndReplayRemainEnforcedWithQAProvider`. The tests preserve normal expiry, invalid-attempt, one-time verification and session behavior. `go test ./internal/auth ./pkg/config` passed in the Windows-host WSL session after the final helper adjustment; the complete migration 001–034 Go/PostGIS runner had also passed earlier in this acceptance run. `bash -n` passed for the OTP reader and isolated start/cleanup scripts.
- Against the isolated API on port 18083, a real OTP request returned HTTP 202 without an OTP field; the runner-only inbox yielded a code once; the ordinary OTP verify endpoint authenticated the allowlisted QA identity; a second inbox read failed; and a non-allowlisted phone was rejected with HTTP 503. No OTP or access token was printed in the validation output. These checks verify QA authentication delivery, not COD acceptance.
- Rebuilt the debug APK with `API_BASE_URL=http://10.0.2.2:18083` (SHA-256 `04bc9a263935a83cee27573b03cdf5b43e8bc1a847735013e7c80cf59ca3eb52`). Installation did not complete. The two QA emulator windows were present, but an existing Pixel_8 and the new customer QA AVD both claimed serial 5554; that transport became offline/authorizing. The rider AVD at 5556 appeared online, but `adb install` returned an empty failure and shell commands stalled after output. The ordinary Windows ADB startup handshake also failed intermittently. A proposed persistent ADB listener bound with `-a` was rejected by automatic security review because it would broaden device-control network exposure; that safeguard was respected. No emulator app data was cleared.
- Removed only the named Phase 4C QA API/Admin/Merchant/MinIO containers, the tmpfs-only migration database, isolated network, and phase-specific QA images. The database had no persistent mounts and used tmpfs. A subsequent Docker query confirmed the shared `grepmind_api`, `grepmind_postgres`, `grepmind_minio`, `grepmind_nginx`, `grepmind_admin_web`, `grepmind_merchant_web`, and `grepmind_worker` containers remained running. The QA records disappeared with the disposable database. No customer order, COD collection, remittance, real payment, or shared-database change was created.
- This attempt was superseded by the final authenticated acceptance below. At the time, QA OTP delivery and normal authentication were verified but device installation did not complete.

## Cleanup and boundary

The automated acceptance runner removed its exact disposable tmpfs PostGIS container. The targeted runtime attempt also removed its exact temporary API, MinIO, database, network and image, and cleared both emulator app sessions. No COD order or remittance was created. Shared services were observed running but were not modified or used for COD transactions. No real cash or money moved. No commit or push was created.

## Final authenticated same-order acceptance (11 November 2026)

- **Isolated environment:** Disposable tmpfs PostGIS database with migrations 001–034, isolated API on `:18083`, QA MinIO, Admin on `:3302`, and Merchant on `:3301`. QA OTP delivery used the allowlisted file-backed adapter. No shared or production database was migrated or used for COD. Synthetic COD/posting was enabled only in this QA database; live UPI, real COD, settlements, and real-money flags remained disabled.
- **Order:** `GN-64E94CFE` / `64e94cfe-48cf-4a6a-a768-c62501c63b4b`, ₹345.00 (34,500 INR minor units), Kuanpal, Cuttack. The Customer created it through the Android app with synthetic COD. The authenticated Merchant Portal advanced the same order through accepted → preparing → ready for pickup. The assigned Rider accepted, verified partner pickup, and completed customer-OTP handover with explicit synthetic collection confirmation. The authenticated Admin Portal retried dispatch for the exact order after the rider came online and later verified the remittance claim.
- **Collection and remittance:** Collection `20b6ad72-30d0-49f1-bd6a-d78af07c1d19` posted once to journal `270bee3b-26d8-447c-82e7-d032cb62226e` (debit 34,500 = credit 34,500). Rider remittance `3e9954b5-cbb8-4740-a1e9-a30c77a6c23a` was submitted once and verified in Admin with a reason; journal `0cef2ce8-bc75-4dd6-ae17-530876a7e463` posted once (debit 34,500 = credit 34,500). Audit history contains one submission and one verification. Rider outstanding liability reconciled from ₹345.00 to ₹0.00; pending and disputed amounts are zero. The only rider earning entry is `unpriced` with no amount, so COD cash was not credited as earnings.
- **Cross-surface/restart:** After the Rider app was force-stopped and relaunched (without clearing app data), the Rider workspace session was restored and Cash accountability showed ₹345.00 collected, ₹345.00 verified remittances, ₹0.00 outstanding, and the same verified remittance history. The Customer app restored the same order as Delivered after restart. The Merchant and Admin browser views showed the same order/remittance state. PostgreSQL confirms order status `delivered`, compatibility `payment_status=not_collected`, method `cash_on_delivery`, COD obligation `collected`, and no payment or payout side effect. No rider GPS, ETA, or customer payment success was shown.
- **Post-submit UI defect and fix:** The first device submission persisted successfully, but the Rider screen then displayed a Flutter framework assertion (`InheritedElement` dependents not empty) before rendering the refreshed history. The remittance and ledger were not duplicated. The two text controllers were moved into a dialog-owned `State` lifecycle so they are disposed only when the dialog subtree is removed. Added `apps/mobile/test/rider_cod_cash_test.dart`; it verifies successful submit, dialog teardown, refreshed history, and no Flutter test exception. The updated APK was rebuilt and installed with update semantics on `emulator-5556`, `emulator-5558`, and `emulator-5560` without clearing data. Because the liability was fully remitted and verified before that rebuild, the fixed submit path was re-exercised by the widget test, while the updated device build verified persisted Rider and Customer state after restart.
- **Build and tests:** Windows-host WSL commands were used: full Flutter tests passed (101); focused analysis for `lib/core/screens/rider_workspace_screen.dart` and `test/rider_cod_cash_test.dart` reported no issues. Full `flutter analyze --no-pub` completed in 90.9 seconds with 18 diagnostics (3 warnings, 15 infos; exit 1, same repository baseline count, none in the changed files). Debug APK built with `API_BASE_URL=http://10.0.2.2:18083`, SHA-256 `E6D1E0278B609ADE35FEAEEFF7CBA76BD9761FA3B53B4E1566D78B4916C32E1D`; update installation succeeded on all three attached emulator serials. The existing full Go/PostGIS suite through migration 034 had passed earlier in Phase 4C; no backend code changed during this closeout.
- **Evidence:** [Customer order after restart](evidence/phase4c-customer-orders-after-restart.png), [Rider remittance after restart](evidence/phase4c-rider-remittance-after-restart.png), and [Admin remittance verification](evidence/phase4c-admin-remittance-verified.png). Images contain only synthetic QA references and amounts; no OTP, address, or phone number is included.
- **Cleanup:** The disposable QA database, API, MinIO, Admin/Merchant containers, QA network, and phase-specific images were removed by exact resource name after evidence capture; temporary browser scripts and OTP/code files were removed. No persistent database volume existed. Shared Grepmind services and emulator app data were preserved. Migration 034 remains unapplied to shared development and production. No commit or push was created.

**Recommendation:** PASS for isolated QA. This does not authorize real cash, production COD, UPI, refunds, merchant settlements, rider payouts, or migration 034 on a shared database. Phase 4D remains unstarted; wait for explicit approval.
