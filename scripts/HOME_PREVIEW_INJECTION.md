# Home tab preview fixtures

The Home preview runner creates a separate, reversible local QA dataset for **Cuttack** and **Jajpur**. It does not reuse or clean `backend/ui-injection-run.json` or any previously retained merchant listing.

From the repository root in Windows PowerShell:

```powershell
./scripts/home_preview_injection.ps1 -Action Inject
```

The script uses the local Compose API/PostgreSQL/MinIO stack. `Inject` also requires a connected Android emulator. It creates four conspicuously labelled `QA PREVIEW` listings per city, uploads four category photographs under a manifest-specific `ui-fixtures/` prefix, publishes one clearly labelled six-day QA offer per city, and builds/launches the app. The open-now listing has a full-week schedule; the service fixture accepts requests; the remaining preview listing demonstrates the recently-added rail. Listing names and descriptions identify these as temporary QA data.

To prepare the records without installing or launching the app, use `-Action Prepare`. This is useful when the emulator still needs manual ADB authorization.

The generated IDs, test phone numbers, and image keys are recorded in `backend/home-preview-injection.json` (file mode 0600 from the Go runner). Keep this manifest while inspecting the emulator. Rebuild or relaunch without injecting again:

```powershell
./scripts/home_preview_injection.ps1 -Action BuildRun
```

Remove only this run's records and images when ready:

```powershell
./scripts/home_preview_injection.ps1 -Action Cleanup
```

Cleanup checks the manifest's run ID and generated user identity before deletion. It deletes only generated fixture users (and their cascading business/offer rows) and exact objects listed in the manifest. The production app is not seeded with sample offers; this preview script is local-only and fails unless the API/database host is loopback and `APP_ENV=local`.
