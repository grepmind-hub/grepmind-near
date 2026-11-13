# Merchant Android Finance Visibility

**State: PASS — isolated QA (13 November 2026).**

This is a separate mobile feature after the original Phase 4D settlement implementation. The original Phase 4D report recorded Merchant Web finance visibility and did not modify mobile code. Grepmind's current product architecture is mobile-first for Merchants: they must be able to inspect financial information in the Android workspace without using Merchant Web.

## Product roles and surfaces

Grepmind Near has exactly four application roles: Customer, Merchant, Rider, and Admin. Finance is an Admin permission/workflow responsibility, not a fifth role or a separate portal. Merchant Android is the primary surface for Merchant orders, products, earnings, payable snapshots, and settlement visibility. Merchant Web remains complementary and is not required for finance visibility.

The Merchant screen is read-only. It does not approve settlements or execute payouts. It clearly distinguishes payable snapshots, pending payable, simulated/reconciled settlements, and actual external payouts. It never labels a simulated amount as paid to bank, and does not claim an available withdrawal balance while real payouts are disabled.

## Implementation

- Replaced the Merchant workspace Earnings placeholder with `MerchantEarningsScreen`.
- Added typed, Riverpod-managed Merchant finance models, repository, and state provider.
- Reuses the existing merchant-scoped Go routes for overview, payables, and settlements.
- Added `simulated_settlement_minor` to the existing overview read response. The Go backend calculates it from only `simulated` and `reconciled` settlement batches for the authorized business; Flutter does not aggregate or derive financial totals.
- Uses the active Merchant profile's business ID. Existing backend owner/manager membership checks continue to enforce tenant isolation.
- Added overview cards, 7/30/90-day and all-history filters, order-level payable details, settlement details, pull-to-refresh, loading, empty, error, and retry states.
- Preserves integer minor units in models and formats displayed amounts using integer arithmetic.
- No migration, new role, new permission, write endpoint, settlement action, or payout control was added.

## Validation status

Automated widget coverage includes server-provided totals, UPI/COD rows, simulation disclosures, detail presentation, history filtering, empty/error/retry states, and history filtering. The full Flutter suite passed (110 tests). Full `flutter analyze --no-pub` completed with 18 diagnostics (3 warnings, 15 infos), matching the recorded baseline; no diagnostics were reported in the new Merchant screen. Full Go tests and the Phase 4D disposable PostGIS validation script passed, including merchant-finance and ownership coverage through migrations 001–037. No shared or production database was migrated.

The QA API was rebuilt from current source on the isolated QA stack only; the existing QA database and order/settlement records were preserved. On the designated Merchant emulator, the authenticated Merchant workspace opened and the Earnings screen read the existing backend records. It showed payable snapshots of ₹220 for `GN-E2F76199` (COD) and ₹220 for `GN-0A130595` (UPI), and reconciled/simulated settlements totaling ₹440. Settlement detail showed the COD funding source as verified COD remittance and UPI funding as the synthetic QA pool. Both were explicitly labeled simulated, not real payouts. Refresh retained the same values. Evidence is in `evidence/phase4d-merchant-android/`.

The same debug APK (versionCode 4008, SHA-256 `B49EDA11802C112E23CC5F1F57105BAB57275E2BED784630CE2B0F18532818AE`) installed successfully on all three designated AVDs: `Pixel_8` / `emulator-5560`, `Pixel_8_Merchant_QA` / `emulator-5558`, and `Pixel_8_Rider_QA` / `emulator-5556`. A fresh ADB daemon check after acceptance was blocked by Windows socket access/daemon handshake errors, so this report relies on the successful install and AVD checks recorded during the live acceptance run. Customer and Rider UI workflows were not part of this Merchant-only feature acceptance; their APK installations were checked, not their role flows.

The Merchant automatic-login runner could not dump the emulator UI (`UiTestAutomationBridge` returned a null root node) and stopped before requesting an OTP. The existing authenticated Merchant session was therefore reused; no OTP was generated or exposed. Merchant Web typecheck could not run because `tsc` is absent from the local dependency tree. These limitations do not change the verified read-only Merchant Android acceptance; no Admin or Merchant Web workflow was modified. `git diff --check` and final scoped results are recorded in the implementation log.

## Financial display semantics

- **Pending payable** is the server's `pending_payable_minor` projection, not an amount available to withdraw.
- **Net payable snapshots** is the server's sum of immutable payable snapshots.
- **Simulated / reconciled** is the server's total of settlement batches in `simulated` or `reconciled` state only.
- History filters affect the returned history rows in the app; overview figures are explicitly labeled all-time server totals.
- Each simulated settlement row retains its server-provided disclosure and does not imply a real transfer.

## Remaining acceptance

1. Merchant Android read-only finance visibility is accepted for isolated QA.
2. Merchant Web finance visibility has since passed its separate final Phase 4D acceptance; see `PHASE_4D_MERCHANT_PAYABLES_AND_SETTLEMENT_SIMULATION.md` and the screenshot in `evidence/phase4d-merchant-web/`.
3. Full analyzer retains 18 baseline diagnostics (3 warnings, 15 infos; exit 1).
4. The Admin finance display was not re-opened in this feature run; current Android values match the preserved isolated QA API/database records and the previously accepted Admin settlement reconciliation.

No shared or production migration was applied. No payment, settlement replay, actual payout, or Phase 4E work occurred. No commit or push was created.
