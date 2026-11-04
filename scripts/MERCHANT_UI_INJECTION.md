# Merchant mobile UI injection

Run in Windows PowerShell with the Windows emulator and local Compose stack running:

```powershell
# Opt-in cycle: inject and delete through the product UI, then clean fixtures.
.\scripts\merchant_ui_injection.ps1 -Action Run

# Validate merchant CRUD and customer conversion flows across every category.
.\scripts\merchant_ui_injection.ps1 -Action Run -Scenario Categories

# If the default ADB port 5037 is unavailable, use a dedicated port.
.\scripts\merchant_ui_injection.ps1 -Action Run -Scenario Categories -AdbServerPort 5039 -DeviceId emulator-5554

# Default action: retain generated products/offers so you can inspect customer listings.
.\scripts\merchant_ui_injection.ps1 -Action Inject

# Remove this script's retained fixtures or recover an interrupted run.
.\scripts\merchant_ui_injection.ps1 -Action Cleanup
```

`-Cities Cuttack,Jajpur` is the default. The script fetches active categories from the API (currently 19). It creates one clearly marked QA merchant/business for each category in each city and one sample product per business (currently 38 products). Fixture profiles reuse an existing city address, generate a dedicated OTP test phone, and populate all seven weekly hours. Category photos are uploaded to a run-scoped `ui-fixtures/<run-id>/` prefix in local MinIO and read by the emulator through Nginx `/media/`. Cleanup removes only keys in that run's manifest.

Account IDs, phone numbers, business IDs, product names/prices and coordinates are generated or derived from existing approved city data. No fixed account credentials, OTPs, tokens, category lists or merchant IDs are embedded. These product names/prices/details are plausible QA samples, not claims of real merchant inventory. Temporary records have a `validation-` marker and are never marked verified.

## What runs through the UI

The Android integration driver mounts the actual `MerchantCatalogScreen`, opens Add Product, enters the sample name, description, price and category image URL, and presses Create Product. It verifies persistence, image retrieval and city/category discovery results. It exercises merchant offer create/update/list/delete through authenticated API routes, checks merchant hours and public business profile data, and selects the real radar map category. The `Categories` scenario additionally opens every generated customer business profile in both cities and verifies category and image metadata, call and WhatsApp intents, save/unsave persistence through the favorites API, published catalog visibility, and operating schedule rendering. `Inject` retains records for review. `Run` opts into a create/delete cycle and removes the generated fixtures.

Account/store setup uses parameterized local SQL because merchant onboarding is not yet connected. Existing merchant scenarios use the real local OTP API and verify merchant/customer roles without driving the onboarding/login UI. The Discovery scenario below drives the customer's onboarding and OTP UI. No scenario mocks HTTP responses or overwrites the emulator user's saved authentication in secure storage. Addresses come from local approved city records; source category photos are copied into local MinIO; contact numbers are generated for OTP testing.

The `Categories` scenario creates, edits and deletes one temporary merchant product per category through the mobile merchant UI, checks customer visibility and image metadata, then adds and removes each business from the QA customer's saved list. Run it with `-Action Run` so generated accounts, businesses, catalog entries, offers and media are removed automatically.

## Merchant appointments and request lifecycle

Run the appointment and request-flow validations against generated local merchants and a generated customer:

```powershell
.\scripts\merchant_ui_injection.ps1 -Action Run -Scenario Availability -DeviceId emulator-5554 -AdbServerPort 5039
.\scripts\merchant_ui_injection.ps1 -Action Run -Scenario Workspace -DeviceId emulator-5554 -AdbServerPort 5039
```

`Availability` covers overlapping-slot rejection, business scoping, date-specific closures, closed-slot booking rejection, merchant-local time display, real customer scheduling, and failed-request recovery. `Workspace` submits a temporary customer request and exercises accept, start work, and complete through the merchant app in both Cuttack and Jajpur, then verifies persisted state and server rejection of an invalid transition. `-Action Run` removes the run's generated records and restores the normal debug APK. Rescheduling to a different slot is not covered because the current backend status endpoint does not accept a replacement slot.

## Customer discovery and OTP UI scenario

Run the reversible end-to-end customer flow with:

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -ExecutionPolicy Bypass -File .\scripts\merchant_ui_injection.ps1 -Action Run -Scenario Discovery -DeviceId emulator-5554
```

`Discovery` prepares a fresh OTP-only customer and temporary image-backed listings for every active category in Cuttack and Jajpur. On the Android emulator, it enters the generated customer's phone number in the real onboarding screen, requests and enters the local development OTP, and verifies the customer session through the real OTP API. It then uses Explore's city/category selectors, checks the listing image URL returns image content, opens a business/service profile, and exercises each category filter plus the image-backed result list in Nearby for both cities. The test keeps its session in memory and does not overwrite the emulator user's saved credentials. `-Action Run` removes only the generated run's users, listings and media, then restores the regular debug APK. It does not send SMS or touch production data.

## WSL and emulator support

- Flutter SDK location is read from `run_mobile.sh`.
- A single device is discovered through Windows ADB; specify `-DeviceId` when multiple devices are connected.
- Temporary host-only Python bridges carry ADB and the authenticated VM-service connection across WSL NAT. Ports are allocated dynamically; the script reserves the Windows ADB forward before WSL's listener to avoid localhost-forwarding conflicts.
- No Windows firewall/settings changes, existing ADB-server shutdown or SDK modification is required. The script stops its own bridge processes and removes its own forward/stop file.
- The normal app is rebuilt for the connected device ABI and reinstalled after testing. `-SkipAppRestore` is available for diagnosis only.

## Cleanup guarantees and limits

The backend recovery ledger is `backend/ui-injection-run.json`. It contains generated IDs/phones, case metadata and exact MinIO object keys, never bearer tokens or OTPs. IDs and upload keys are recorded before insertion and the ledger is atomically replaced. Cleanup checks the run UUID/object prefix, removes only those objects and generated dependent records, verifies generated users are gone, then removes the ledger. Successful `Inject` runs intentionally retain data. Cleanup is a separate explicit command; `Run` is an opt-in cycle. A failed scripted run cleans partial fixtures, while a forced shutdown preserves the manifest for explicit recovery.

If Windows is killed or the machine shuts down, no script can execute its finalizer at that instant. Keep the ledger and run `-Action Cleanup` after recovery. Never remove the ledger manually before cleanup. The runner refuses a new run when a recovery ledger exists. Supported targets are the local API/database and emulator loopback endpoints; production use is rejected.

GPS/map assertions validate persisted city/category/radius results. They do not certify municipality boundary polygons, Google tile rendering, or Android permission dialogs. When GPS lies outside the selected city's search radius, the app shows no nearby listings and offers searching the selected city center.
