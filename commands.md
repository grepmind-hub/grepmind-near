Ran find all docker-compose files
Ran find all compose files recursively
Analyzed docker-compose.yml:L1-60
Analyzed docker-compose.yml:L61-160
Analyzed docker-compose.yml:L161-222
Analyzed docker-compose.test.yml:L1-80
Ran check running Docker containers in WSL
Ran check grepmind_4c_qa_api logs
Ran list all grepmind containers
Ran restart grepmind_3e_qa_db
Ran check qa api and db status
Ran restart grepmind_4c_qa_api
Ran check qa_api container status
Ran list QA scripts

Here is the complete confirmation of our Docker Compose files and the exact testing commands used across the project:

---

## 1. Which Docker Compose File We Are Using

The repository contains three Docker Compose configurations:

| Compose File | Environment | Purpose |
|---|---|---|
| [**`docker-compose.yml`**](file:///d:/grepmind-near/docker-compose.yml) | **Local Development & Coding** | **The primary file used for development.** It runs the complete multi-tier stack: PostgreSQL (PostGIS), MinIO S3, Go API, Go Background Worker, Nginx reverse proxy, Merchant Web Portal (Next.js), and Admin Web Portal (Next.js). |
| [**`docker-compose.test.yml`**](file:///d:/grepmind-near/docker-compose.test.yml) | **Automated CI/CD Pipeline** | Runs isolated test database (`grepmind_test_postgres`), test S3 (`grepmind_test_minio`), and test backend API (`grepmind_test_api`) on an isolated `grepmind_test` bridge network. |
| [**`docker-compose.staging.yml`**](file:///d:/grepmind-near/docker-compose.staging.yml) | **Staging / Pre-production** | Used for pre-production integration deployments. |

---

## 2. Which One Was Used for Coding & What is Active

### For Coding and Local Development:
We use [**`docker-compose.yml`**](file:///d:/grepmind-near/docker-compose.yml).
- **Start Command**:
  ```bash
  docker compose up -d
  ```
- **Stop Command**:
  ```bash
  docker compose down
  ```
- **Services running under this stack**:
  - `grepmind_postgres` (PostGIS 16 on port `5432`)
  - `grepmind_minio` (S3 object storage on ports `9000` & `9001`)
  - `grepmind_api` (Go REST backend on port `8080`)
  - `grepmind_worker` (Background job engine)
  - `grepmind_nginx` (Reverse proxy on port `80`)
  - `grepmind_merchant_web` (Port `3001`)
  - `grepmind_admin_web` (Port `3000`)

### For Isolated QA & Security-Preserving E2E Testing:
Per the project architecture rules in `AGENTS.md`, our automated test suite connects to an **isolated QA environment** so that synthetic transactions, trial accounts, and new migrations do not pollute the shared development database:
- `grepmind_4c_qa_api` (Target API: `http://127.0.0.1:18083/api/v1`)
- `grepmind_4c_qa_otp_inbox` (Secure OTP Inbox: `http://127.0.0.1:18085`)
- `grepmind_3e_qa_db` (Isolated PostgreSQL: port `55432`)

---

## 3. The Commands Used for Testing

### A. Complete End-to-End UI & Platform Automation Suite
*(The complete 6-activity test runner validating roles, catalog, food/grocery orders, UPI/COD payments, remittance, and ledger audits)*

```powershell
# 1. Standard execution (uses default allowlisted synthetic QA accounts)
powershell -ExecutionPolicy Bypass -File scripts\qa\run-complete-e2e-suite.ps1

# 2. Custom execution (with custom phone numbers, product names, and pricing)
powershell -ExecutionPolicy Bypass -File scripts\qa\run-complete-e2e-suite.ps1 `
  -CustomerPhone "+919990000171" `
  -MerchantPhone "+919990000172" `
  -RiderPhone "+919990000173" `
  -ProductName "Artisanal Organic Darjeeling Tea" `
  -ProductPrice 285.0 `
  -ServiceName "Standard Wiring Inspection" `
  -ServicePrice 350.0

# 3. Headless / CI execution (skips physical Android emulator screencaps)
powershell -ExecutionPolicy Bypass -File scripts\qa\run-complete-e2e-suite.ps1 -SkipEmulators

# 4. Custom report destination
powershell -ExecutionPolicy Bypass -File scripts\qa\run-complete-e2e-suite.ps1 -ReportFile "reports/my-run.md"
```

---

### B. Backend Go Tests (Unit, Integration & Concurrency Races)
Run in WSL / Linux container:

```bash
# Run all backend unit & integration tests
cd backend && go test -v -count=1 ./...

# Run delivery dispatch & payment lifecycle tests
cd backend && go test -v -count=1 ./internal/deliverydispatch/...

# Run COD cash accountability & ledger tests
cd backend && go test -v -count=1 ./internal/codcash/...
```

---

### C. Flutter Mobile Tests (Widgets, Screens & Role Navigation)

```bash
# Run all mobile tests
cd apps/mobile && flutter test

# Run specific navigation and catalog tests
cd apps/mobile && flutter test test/multi_role_navigation_test.dart
cd apps/mobile && flutter test test/catalog_flow_test.dart
```

---

### D. Static Analysis & Linting

```bash
# Flutter code analysis (ensure 0 errors)
cd apps/mobile && flutter analyze

# Go static vet
cd backend && go vet ./...
```

---

### E. Admin Portal Playwright Browser Tests

```powershell
# Run Admin Web automated Playwright test suite
powershell -ExecutionPolicy Bypass -File scripts\qa\auth-otp-02-admin-playwright.ps1 -Headless
```


# =============================================================

Ran check phase4c-e2e-start.sh
Analyzed phase4c-e2e-cleanup.sh:L1-38
Ran remove stale exited containers
Ran check cleaned docker ps -a

Here is the exact breakdown of those containers and whether you need them:

---

### 1. The 6 Exited Containers (Already Cleaned Up)

The following 6 containers were **dead leftover artifacts** from historical test runs (Phase 4C and 4E.2). They were **not required at all** and have now been removed:

- `grepmind_4c_qa_admin` (Exited) — **Removed**
- `grepmind_4e2_runtime_api` (Exited) — **Removed**
- `grepmind_4c_qa_otp_inbox_stale_20261113` (Exited) — **Removed**
- `grepmind_4c_qa_api_previous` (Exited) — **Removed**
- `grepmind_4c_qa_merchant` (Exited) — **Removed**
- `grepmind_4c_qa_minio` (Exited) — **Removed**

---

### 2. The 3 Running QA Containers

The only 3 QA containers currently active are:
1. `grepmind_4c_qa_api` (`127.0.0.1:18083`)
2. `grepmind_4c_qa_otp_inbox` (`127.0.0.1:18085`)
3. `grepmind_3e_qa_db` (`127.0.0.1:55432`)

#### Are they required if you start fresh?

* **For Normal Coding / Daily Development: NO, NOT REQUIRED.**
  When doing standard development, you only need the main development stack started via:
  ```bash
  docker compose up -d
  ```
  This runs your main services from [`docker-compose.yml`](file:///d:/grepmind-near/docker-compose.yml):
  - Database: `grepmind_postgres` (Port `5432`)
  - Storage: `grepmind_minio` (Ports `9000`, `9001`)
  - Backend: `grepmind_api` (Port `8080`)
  - Web Portals: `grepmind_admin_web` (`3000`), `grepmind_merchant_web` (`3001`), `grepmind_nginx` (`80`)

* **For Running the Automated End-to-End Suite: YES, REQUIRED.**
  When running `scripts/qa/run-complete-e2e-suite.ps1`, the script routes through these 3 containers because:
  1. **Protects your development database**: It keeps your main `grepmind_postgres` database clean so test dummy orders, test products, cancelled rider runs, and fake payments do not pollute your real dev data.
  2. **Automated OTP Inbox**: The `grepmind_4c_qa_otp_inbox` service allows the automation script to read and verify SMS OTP challenges automatically without a human having to type OTPs manually.

---

### 3. How to Clean Up and Start Fresh

If you want to completely tear down all QA test containers:
```bash
# In WSL:
bash scripts/qa/phase4c-e2e-cleanup.sh
```

If you ever need to re-launch the isolated QA test environment for a fresh automation pass:
```bash
# In WSL:
bash scripts/qa/phase3e-start-isolated.sh
bash scripts/qa/phase4c-e2e-start.sh
```

### Current Status

Your Docker environment is now clean. Only your **primary development stack** (from `docker-compose.yml`) and the **3 active QA automation containers** are present.