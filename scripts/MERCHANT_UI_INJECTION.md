# Merchant mobile UI injection

Run in Windows PowerShell with the Windows emulator and local Compose stack running:

```powershell
# Opt-in cycle: inject and delete through the product UI, then clean fixtures.
.\scripts\merchant_ui_injection.ps1 -Action Run

# Default action: retain generated products/offers so you can inspect customer listings.
.\scripts\merchant_ui_injection.ps1 -Action Inject

# Remove this script's retained fixtures or recover an interrupted run.
.\scripts\merchant_ui_injection.ps1 -Action Cleanup
```

`-Cities Cuttack,Jajpur` is the default. The script fetches active categories from the API (currently 19). It creates one clearly marked QA merchant/business for each category in each city and one sample product per business (currently 38 products). Fixture profiles reuse an existing city address, generate a dedicated OTP test phone, and populate all seven weekly hours. Category photos are uploaded to a run-scoped `ui-fixtures/<run-id>/` prefix in local MinIO and read by the emulator through Nginx `/media/`. Cleanup removes only keys in that run's manifest.

Account IDs, phone numbers, business IDs, product names/prices and coordinates are generated or derived from existing approved city data. No fixed account credentials, OTPs, tokens, category lists or merchant IDs are embedded. These product names/prices/details are plausible QA samples, not claims of real merchant inventory. Temporary records have a `validation-` marker and are never marked verified.

## What runs through the UI

The Android integration driver mounts the actual `MerchantCatalogScreen`, opens Add Product, enters the sample name, description, price and category image URL, and presses Create Product. It verifies persistence, image retrieval and city/category discovery results. It exercises merchant offer create/update/list/delete through authenticated API routes, checks merchant hours and public business profile data, opens the customer profile screen, verifies schedule rendering, and intercepts phone and WhatsApp intents. It also selects the real radar map category and checks the fixture marker. `Inject` retains records for review. `Run` opts into a create/delete cycle and removes the generated fixtures.

Account/store setup uses parameterized local SQL because merchant onboarding is not yet connected. Login uses the real local OTP API and verifies merchant/customer roles. The automation does not drive the onboarding/login UI, does not mock HTTP responses, and does not overwrite the emulator user's saved authentication in secure storage. Addresses come from local approved city records; source category photos are copied into local MinIO; contact numbers are generated for OTP testing.

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
