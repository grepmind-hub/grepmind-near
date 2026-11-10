# Phase 2R.2 — Customer Orders Shopping Hub

**Date:** 6 November 2026  
**Implementation status:** Implemented and runtime-validated with four temporary, scoped QA products; all QA products and images were removed after validation.  
**Scope:** Customer Orders hub and platform-owned Food/Grocery catalog browsing only.

## Delivered

- Replaced the Customer Orders tab landing page with a Grepmind shopping hub: delivery location, catalog search, disabled platform-cart entry, Food & Meals and Groceries entry cards, backend-backed featured products when available, Active orders and My Orders shortcuts.
- Added platform catalog models and read-only repository providers for the Phase 2R.1 public categories, products, and exact product detail APIs. Requests include Food/Grocery vertical and supported city/locality; search is debounced, categories come from the API, and product results support offset pagination.
- Added a responsive catalog grid with API images, platform selling prices from integer minor units, category filters, empty/error/offline/retry states, and exact product detail reload. No merchant settlement values are parsed or displayed.
- Added an Orders-local Navigator and explicit system Back dispatch so product details and My Orders return to the shopping hub before the workspace Back behavior switches to Home.
- Kept the old merchant cart unconnected. Platform cart and Add to Cart are disabled and labeled unavailable until Phase 2R.3; no platform order can be submitted.
- Added a stable delivery hierarchy API and schema: Odisha → Cuttack/Jajpur districts → Kuanpal, Jagatpur, Tangi, Chhatia, Chandikhol localities. Kuanpal and Chhatia are enabled for QA; Jagatpur, Tangi and Chandikhol are configured but not deliverable. Orders-local selection persists district/locality independently from discovery location.
- Catalog visibility is district-scoped while delivery eligibility is locality-scoped. Requests use stable locality IDs and reject a locality paired with the wrong district.
- The shopping flow offers Cuttack and Jajpur only. Unsupported saved discovery cities require choosing a supported district. No non-QA product, image, price, stock, offer, ETA, or order count was inserted.

## Changed files

- `apps/mobile/lib/main.dart`
- `apps/mobile/lib/core/models/platform_catalog.dart`
- `apps/mobile/lib/core/providers/platform_catalog_provider.dart`
- `apps/mobile/lib/core/screens/order_shopping_hub_screen.dart`
- `apps/mobile/lib/core/screens/orders_tab_navigator.dart`
- `apps/mobile/lib/core/screens/platform_catalog_screen.dart`
- `apps/mobile/lib/core/screens/platform_product_detail_screen.dart`
- `apps/mobile/test/platform_catalog_test.dart`
- `backend/migrations/022_delivery_locality_hierarchy.sql`
- `backend/internal/platformcatalog/service.go`
- `backend/internal/platformcatalog/service_test.go`
- `scripts/qa/phase2r2_locality_catalog.py`
- `api/openapi.yaml`
- `apps/mobile/test/workspace_navigation_test.dart`
- `AGENTS.md`
- `codex-implementation.md`
- `docs/phases/README.md`
- `docs/phases/PHASE_2R_2_CUSTOMER_ORDERS_SHOPPING_HUB.md`

Migration 022 adds districts, delivery localities, separate product district-visibility and locality-delivery mappings, and partner delivery-locality coverage. It was tested on a disposable database, then applied transactionally to the local development database with approval. The existing migration 021 was not edited. Only the API container was rebuilt.

## Validation evidence

- `flutter test --no-pub test/platform_catalog_test.dart`: **4 passed**, including district/locality selection reset and locality ID propagation. Full Flutter suite was not rerun in this acceptance recovery.
- `go test ./internal/platformcatalog ./cmd/api`: **PASS**. Full `go test -count=1 ./...` rerun was blocked because this Codex execution environment returned `Wsl/E_ACCESSDENIED` before the command entered Ubuntu WSL.
- Targeted `dart analyze` over all Phase 2R.2 implementation and test files: **No issues found**.
- Full `flutter analyze --no-pub`: **118 diagnostics**, matching the recorded baseline of 118; no increase. Targeted analysis of all changed Phase 2R.2 implementation and test files reports no issues. The full analyzer command exits 1 because existing project diagnostics remain.
- `./scripts/mobile_emulator.ps1 -Action Build`: **PASS**, generated the latest `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk` (233,083,102 bytes) using Flutter 3.47.8 in WSL and the existing emulator API define `http://10.0.2.2:80`.
- Windows ADB on port 5039 and the Pixel 8 emulator were recovered with the supported `Start` action. Direct `adb install -r -t` of the APK then returned **Success**; `pm path local.grepmind.grepmind_mobile` confirmed the installed package. `am start -n local.grepmind.grepmind_mobile/.MainActivity` launched successfully.
- A fresh, randomly generated customer phone was confirmed unused before test login. The real Flutter OTP UI used the local development stub; no SMS was sent. Customer mode was selected through the app. After validation, app storage was cleared and the fresh QA user, OTP rows, and cascading session/role records were removed. Verification confirmed no matching user or OTP remained.
- Emulator screenshots: `apps/mobile/build/phase2r2-orders.png` (hub), `apps/mobile/build/phase2r2-food.png` (Food empty state), `apps/mobile/build/phase2r2-grocery.png` (Grocery empty state), `apps/mobile/build/phase2r2-my-orders.png` (existing order-history empty state), `apps/mobile/build/phase2r2-restart.png` (authenticated session restored after force-stop/relaunch), and `apps/mobile/build/phase2r2-clean-login.png` (signed-out final state). Phone/OTP screenshots and XML dumps were removed after automation; no customer number or OTP is recorded.
- Authenticated UI checks passed for Customer workspace entry; Orders hub; Food catalog in Cuttack and Jajpur; Grocery catalog in Jajpur; supported location selection; grocery `rice` search returning the true empty state; My Orders opening the existing history screen; Android Back returning to the hub; and force-stop/relaunch restoring the customer session. No real platform products existed, so product cards, price rendering, image fetches, product detail, and non-empty search results could not be validated on device.
- The platform cart icon and message are visibly disabled on the hub. Widget test `Orders hub opens catalog and exact product details without cart success` asserts `onPressed == null` for both cart and Add to Cart, so the legacy merchant cart is not wired in. A separate post-restart emulator tap assertion was inconclusive due to navigation timing; no legacy cart screen was observed.
- API root cause: direct API (`http://localhost:8080`) and Nginx (`http://localhost`) both returned 200 for `/healthz` and 404 for catalog routes before recovery. Nginx preserves `/api/` and was not the cause. Current source registers routes in `backend/cmd/api/main.go`; image `grepmind-near-api` had been built before that source. Read-only DB checks found 33 application tables and no migration ledger/catalog schema. With approval, `backend/migrations/021_platform_catalog.sql` was applied using one PostgreSQL transaction. It created the catalog/partner tables and seeded only Food and Grocery root categories. No products, mappings, or QA catalog fixtures were inserted.
- Location hierarchy migration 022 was separately dry-run on a disposable PostgreSQL database and then applied to local development with approval. It seeded only district/locality configuration and made no products. Four QA catalog fixtures were later created for the approved populated-catalog acceptance below.
- Rebuilt/restarted only API via `docker compose up -d --no-deps --build api`; PostgreSQL and other services were not recreated. The API is healthy. Direct and Nginx smoke checks across all four Food/Grocery × Cuttack/Jajpur combinations returned categories **200, count 1** and products **200, count 0**. Unknown product detail returned **404**; unsupported Bhubaneswar city returned **400**; `/healthz` returned **200**. Product-detail success and settlement-cost omission from a non-empty public product response remain unverified because no product exists. Previous Phase 2R.1 disposable-database tests cover public response field omission.
- The existing Compose migration strategy mounts scripts into PostgreSQL's `/docker-entrypoint-initdb.d`; no migration ledger or runtime migration runner was found. Migration 021 is applied locally now, but version tracking/backup automation remains a separate production-hardening concern.
- During authenticated Home navigation, pre-existing `QA preview` offer/service cards were visible. They were not created by this run and were left untouched as out of Phase 2R.2 scope.

### Delivery locality and populated catalog acceptance recovery

- Local API service was rebuilt using the current source and migration 022, without recreating PostgreSQL or other Compose services. `GET /api/v1/catalog/locations` returned stable district/locality IDs and enabled/planned delivery status through the API; the public Nginx route was also checked. Cross-district locality ID returned HTTP 400; a planned locality returned an empty product list with `delivery_available:false`.
- Created exactly four Admin-API QA products and four distinct QA PNG images: QA Chicken Biryani and QA Rice 1 kg for Cuttack/Kuanpal; QA Veg Thali and QA Milk 1 L for Jajpur/Chhatia. Each was marked temporary QA with explicit test price and local image. No partner assignment, stock claim, customer order or payment was created.
- The QA validation script verified each district/locality/category combination, exact detail, image HTTP 200, price, search, district-level visibility, no partner settlement fields, cross-district rejection, and planned-locality unavailable state. All 10 checks passed.
- Latest APK was rebuilt, installed and launched on Pixel 8. Authenticated UI showed real catalog product names, backend prices and images in both districts/localities; Food and Grocery pages and a product detail rendered, search found the expected item, planned Jagatpur showed delivery unavailable, and My Orders opened with no fabricated order. The district chip correction was tested: selecting Jajpur exposed Chhatia (not Cuttack localities); selecting Cuttack exposed Kuanpal. Orders-local location selection did not change global discovery city.
- Screenshot evidence is in `apps/mobile/build/phase2r2-orders-qa.png`, `phase2r2-kuanpal-food.png`, `phase2r2-kuanpal-grocery.png`, `phase2r2-food-detail-qa.png`, `phase2r2-jajpur-food.png`, `phase2r2-jajpur-grocery.png`, `phase2r2-milk-detail.png`, `phase2r2-planned-locality.png`, and `phase2r2-chhatia-hub-fixed.png`.
- QA cleanup completed through the WSL-connected VS Code terminal. The script reported removal of four QA products and four images. PostgreSQL verification returned zero rows for QA product SKUs, variants, media-upload rows, district-visibility mappings, locality-delivery mappings, and legacy product-area mappings. MinIO verification returned zero objects under the QA prefix. The local manifest is deleted. No customer order was created; immutable administrative audit events may remain by design.
- WSL startup diagnosis: plain `wsl` through the restricted PowerShell command runner returned `Wsl/E_ACCESSDENIED`. The active VS Code terminal is a WSL Ubuntu shell at `/mnt/d/grepmind-near`; running plain `wsl` from the Windows host through the approved execution path opened the same configured distribution. All final cleanup and test commands ran in that shell, so this was a command-runner boundary, not a WSL distro failure.
- Final commands: `cd backend && go test -count=1 ./...` — PASS; `cd ../apps/mobile && flutter test --no-pub` — PASS, **70 tests**; `flutter analyze --no-pub` — **18 diagnostics** (3 warnings, 15 infos, 0 errors), command exits 1 due to remaining warnings/info. Prior Phase 2R.2 notes recorded 118 diagnostics; this run reports fewer, with no analyzer errors. Final API smoke through Nginx confirmed all four Food/Grocery × Cuttack/Jajpur locality combinations return HTTP 200 with zero products after cleanup. `GET /api/v1/catalog/locations` returns Cuttack/Jajpur and all five locality enabled/planned states. Earlier QA API validation passed 10 checks and emulator screens showed the four product cards/prices/images/details before cleanup.

## Acceptance

**PASS — Phase 2R.2 acceptance complete.** Stable district/locality hierarchy, separate district visibility and locality delivery rules, all four QA catalog paths, product names/prices/images/details/search, planned-locality state, My Orders access, and cleanup were verified. PostgreSQL confirms zero QA products, variants, media records and product mappings; MinIO confirms zero QA objects. Full Go tests and all 70 Flutter tests passed. Flutter analysis has 18 non-error diagnostics (3 warnings and 15 informational lints) and exits 1; the prior recorded count was 118. Phase 2R.3 has not started; stop here pending explicit approval.
