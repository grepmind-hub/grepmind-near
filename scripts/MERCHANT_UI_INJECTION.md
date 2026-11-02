# Merchant mobile UI injection

Run in Windows PowerShell with the Windows emulator and local Compose stack running:

```powershell
# Create products through the merchant UI, verify them, delete through UI, and clean fixtures.
.\scripts\merchant_ui_injection.ps1 -Action Run

# Keep injected products so you can inspect customer listings and the map.
.\scripts\merchant_ui_injection.ps1 -Action Inject

# Remove this script's retained fixtures or recover an interrupted run.
.\scripts\merchant_ui_injection.ps1 -Action Cleanup
```

`-Cities Cuttack,Jajpur` is the default. The script fetches all active categories from the API (currently 19). It creates a separate temporary merchant/business for each taxonomy category in each city and one product per business: currently 38 products. A business has one primary discovery category; this does not create 19 product groups inside one existing store. Existing merchants and their catalog entries are not used or changed.

Account IDs, phone numbers, business IDs, product names/prices and coordinates are generated or derived from existing approved city data. No fixed account credentials, OTPs, tokens, category lists or merchant IDs are embedded. Temporary records have a `validation-` marker and are never marked verified.

## What runs through the UI

The Android integration driver mounts the actual `MerchantCatalogScreen`, opens Add Product, enters the generated name/price and presses Create Product. It verifies public API visibility and matching city/category nearby results. It also opens the real radar map screen, selects the live category chip and asserts the generated business marker and city/category results. Run mode creates all products, then opens each real delete confirmation and verifies removal. It does not insert products directly into PostgreSQL.

Account/store setup uses parameterized local SQL because merchant onboarding is not yet connected. Login uses the real local OTP API and verifies the merchant role. The automation does not drive the onboarding/login UI, does not mock HTTP responses, and does not overwrite the emulator user's saved authentication in secure storage.

## WSL and emulator support

- Flutter SDK location is read from `run_mobile.sh`.
- A single device is discovered through Windows ADB; specify `-DeviceId` when multiple devices are connected.
- Temporary host-only Python bridges carry ADB and the authenticated VM-service connection across WSL NAT. Ports are allocated dynamically; the script reserves the Windows ADB forward before WSL's listener to avoid localhost-forwarding conflicts.
- No Windows firewall/settings changes, existing ADB-server shutdown or SDK modification is required. The script stops its own bridge processes and removes its own forward/stop file.
- The normal app is rebuilt for the connected device ABI and reinstalled after testing. `-SkipAppRestore` is available for diagnosis only.

## Cleanup guarantees and limits

The backend recovery ledger is `backend/ui-injection-run.json`. It contains generated IDs/phones and case metadata, never bearer tokens or OTPs. IDs are recorded before insertion and the ledger is atomically replaced. Cleanup checks exact run ownership, removes dependent records transactionally, verifies generated users are gone, then removes the ledger. A failed run also cleans up. Run mode deletes products through UI first; ledger cleanup handles remaining setup data and interrupted/failed UI operations. Inject mode keeps fixtures only after success.

If Windows is killed or the machine shuts down, no script can execute its finalizer at that instant. Keep the ledger and run `-Action Cleanup` after recovery. Never remove the ledger manually before cleanup. The runner refuses a new run when a recovery ledger exists. Supported targets are the local API/database and emulator loopback endpoints; production use is rejected.

GPS/map assertions validate persisted city/category/radius results. They do not certify municipality boundary polygons, Google tile rendering, or Android permission dialogs. When GPS lies outside the selected city's search radius, the app shows no nearby listings and offers searching the selected city center.
