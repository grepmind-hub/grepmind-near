# Local city/category automation

Run from Windows PowerShell in this repository:

```powershell
./scripts/test_merchant_categories.ps1 -Cities Cuttack,Jajpur
```

Or from WSL:

```bash
cd /mnt/d/grepmind-near/backend
APP_ENV=local DB_HOST=127.0.0.1 go run ./cmd/validate-cities --cities Cuttack,Jajpur --allow-local-fixtures
```

The local Compose API and PostgreSQL must be running with migration 009 applied. The runner uses the existing Go PostgreSQL driver; no additional dependency is required. Database configuration comes from the backend's DB_* environment variables. API and database must both be the same local stack. The runner rejects non-loopback targets and requires explicit fixture permission.

## Data-driven coverage

The script reads active categories from `/categories` and city coordinates from existing approved database listings. It generates unique account IDs, phone numbers, business IDs, catalog names and payloads. There are no fixed merchant credentials, customer credentials, OTPs, business IDs or expected category lists. Cities are test parameters.

It creates one temporary customer and a separate merchant/store per city/category combination. Login uses the real local OTP request/verify API; tokens and OTPs remain in memory and are never written to the manifest or output.

For every city/category it validates:

- Merchant category create, rename, list and delete persistence.
- Product and service create, update, customer visibility, delete and disappearance.
- Exact city plus category plus query filtering, including wrong-city rejection.
- Customer booking creation, merchant acceptance, and customer-visible status.
- Anonymous and customer category-mutation denial; unrelated-merchant category and booking access denial.

These are API/database integration checks, not emulator UI automation. An empty real category in a city is not represented as real inventory: generated listings exist only during the test and are removed.

## Cleanup and interrupted-run recovery

Before insertion the script records allocated user IDs and phone numbers in `backend/city-validation-run.json`. It verifies each user's exact ID, phone, and per-run display marker before deleting anything. Normal completion and failures both run transactional cleanup. Existing user and business records are never used as fixtures or modified.

Cleanup removes generated requests and notifications before generated accounts; foreign-key cascades remove their businesses, categories, products, services, memberships, favorites and sessions. OTP records belonging to those generated accounts are removed explicitly. It verifies no run-owned accounts remain and deletes the manifest only after successful cleanup.

If the process is killed, Windows restarts, or database access fails, retain the manifest and run:

```powershell
./scripts/test_merchant_categories.ps1 -Cleanup
```

The runner refuses to start a new run when an existing manifest needs recovery. Do not delete that manifest manually before cleanup. Never use the local OTP stub or fixture runner against production.
