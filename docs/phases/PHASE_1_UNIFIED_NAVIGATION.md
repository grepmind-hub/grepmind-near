# Phase 1 — Unified navigation and role foundation

**Completed:** 6 November 2026
**Acceptance:** PASS with the account-data limitation below.
**Scope:** Unified Customer, Merchant, and backend-authorized Rider navigation; no Phase 2 commerce implementation.

## Delivered

| Workspace | Tabs | Evidence / behavior |
|---|---|---|
| Customer | Home, Explore, Nearby, Orders, Profile | Orders is a first-class tab; Saved is opened from Profile and retains the existing saved-business screen and API behavior. |
| Merchant | Dashboard, Orders, Catalog, Earnings, Profile | Reuses the existing merchant workspace and catalog. Orders and Earnings are explicitly labeled unavailable; no fake revenue/order totals were added. |
| Rider | Dashboard, Deliveries, Map, Earnings, Profile | Shown only when `/api/v1/me` includes the `rider` role. Operational surfaces explain they are unavailable; no rider onboarding, dispatch, payment, or GPS tracking was built. |

The workspace switcher and restore path use backend role data. Merchant entry allows `merchant` or `professional`; Rider entry requires backend `rider` approval. The role-assignment path remains root-superadmin protected. Migration `017_rider_role.sql` is additive and was applied to the local Compose DB after validating existing role values.

Visited tabs mount lazily and retain state; `TickerMode` pauses inactive tab animations. This prevents hidden Explore/Nearby/Orders work from running on the initial Home view. Home and Explore now share default city loading, so Home does not depend on Explore having mounted. Nearby location subscriptions continue to be disposed with the screen. No new workspace SSE subscription was introduced.

Android Back from a non-root workspace tab returns to that workspace's root tab. Merchant isolation, authentication, saved businesses, existing booking flows, and SSE configuration were preserved.

## Validation evidence

- `flutter test --no-pub`: PASS, 58 tests, including Home default-city loading and role/navigation coverage.
- `flutter analyze --no-pub`: 119 diagnostics, same count as the recorded pre-implementation baseline; analyzer remains non-clean and exits nonzero.
- `go test ./...`: PASS.
- Admin portal `npm run typecheck`: PASS.
- `git diff --check`: PASS.
- Existing `scripts/mobile_emulator.ps1 -Action BuildRun ... -ApiBaseUrl http://10.0.2.2:80`: PASS. Debug APK built with Flutter 3.47.8 in WSL, installed and launched on Windows emulator `emulator-5554`.
- Emulator UI checks: Customer Home selected Cuttack; Orders opened; Android Back returned to Home; Saved opened from Profile; role chooser showed authorized Customer/Merchant roles and Rider locked; Merchant workspace and Catalog navigation opened; Earnings showed its unavailable state; Merchant workspace restored after force-stop/relaunch.
- Screenshots are in the local Windows temp directory as `grepmind-phase1-final-home.png`, `grepmind-phase1-final-orders.png`, `grepmind-phase1-final-saved.png`, `grepmind-phase1-final-role-sheet.png`, `grepmind-phase1-final-merchant.png`, `grepmind-phase1-final-merchant-catalog.png`, `grepmind-phase1-final-merchant-earnings.png`, and `grepmind-phase1-final-session-restore.png`.

## Acceptance limits

- The local QA identity had Customer and Merchant roles but no assigned business. Merchant workspace access and empty states were checked, but merchant-specific product/order records and cross-business operations were not exercised on-device in this phase.
- Rider was correctly denied because the account lacked backend approval. An approved rider and live operational rider workflow were intentionally not tested or implemented.
- The 119 analyzer findings remain technical debt; a stable baseline count is not a clean analyzer result.
- The implementation was not deployed. Phase 2 has not begun in source code.

## Change inventory

Phase 1 source changes cover the role model/API documentation, Admin rider access control, Flutter workspace navigation, profile Saved/switcher entry points, shared location initialization, backend rider role validation, and focused tests. See the Phase 1 section in [`codex-implementation.md`](../../codex-implementation.md) for the working-tree change record. Environment helper/config changes and QA injection fixtures already present in the worktree were not part of this Phase 1 source change inventory.
