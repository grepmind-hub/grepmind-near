# Abashyaka internal deployment result — 20 November 2026## Subsequent tunnel and URL checkAfter the user supplied the token and approved starting the connector, `abashyaka-cloudflared` was started. The token file is owner `devserver`, mode 0600; its contents were not displayed. The latest 100 connector log lines included four registered tunnel connections and no tunnel/connection error lines. PostgreSQL, MinIO, API, Admin and Nginx are healthy; Merchant web remains stopped. The connector has no Docker healthcheck and is reported running, not independently healthy.HTTPS requests executed from the Ubuntu host: API `/healthz`, `/api/v1/categories`, and `/api/v1/catalog/locations` returned 200; anonymous `/api/v1/merchant/businesses` and `/api/v1/events` returned 401. `https://abashyaka.com/` returned 200; its content and hosting identity were not verified. `admin.abashyaka.com` and `merchant.abashyaka.com` did not resolve in that host's DNS. The separate web browsing tool could not access these URLs, so independent external-network reachability is not established. No DNS or Cloudflare route changes were made by the agent. Admin remains reachable internally; its login page/assets and same-origin API proxy passed HTTP checks. Merchant web remains intentionally stopped and its internal Host returns 404.The API security/configuration smoke checks passed again; both private MinIO buckets passed restricted-account write/read/delete probes. Authentication, authenticated merchant isolation, and live SSE remain untested; SMS and payment simulation remain disabled. Existing public routes should be reviewed in Cloudflare, including Access enforcement before Admin exposure. The prior references below to the connector being inactive describe the earlier checkpoint.

**Overall: PARTIAL acceptance. Internal deployment health gate PASS; public activation BLOCKED pending security remediation and approval.** This supersedes the earlier directory-blocked attempt. No Cloudflare connector, DNS change, public ingress, Android build or feature development occurred.

## Source and release — PASS

- Checkout: `D:\grepmind-near`, branch `abashyaka-dev-02`, commit `8d5eb0fec1e10417073c01419201ac1859c3e78c`. `abashyaka-dev-01` remains at the same commit.
- Remote release: `/opt/abashyaka/releases/8d5eb0f-d03`; Docker project `abashyaka`. Existing release paths were not overwritten during extraction.
- Existing mobile edits are unchanged, verified by SHA-256: screen `03982411e0b4b8b3efe39456230cbba53b68046351a79cb95a3b4f698b0f97ab`; test `74094f54beab8af07e150d3ff84a68855730b8085fc23ee7ecdbb85104563591`.
- Verified directory modes: releases `devserver:devserver 0750`, secrets `devserver:devserver 0700`. The operator created them interactively; no sudo policy or SSH credential changes were made.

| Transferred artifact | SHA-256 (local and remote verified) |
|---|---|
| `abashyaka-base-clean.tar.gz` | `5cbaf640dcc8411608edcfd5ffe645709749c3ff16f36567ae7fc0b22a7b0195` |
| `abashyaka-overlay-d03.tar.gz` | `8c5c72ff8f8acb12fdd4de1d06056295761ae71e9454087a2f268742ba7938e2` |
| `abashyaka-config-d03-final.tar.gz` | `810273b4b772ad61c0072993c7cfbe14ed1fbb098c7f6c01bfdef9fed1cec164` || `abashyaka-config-mobile-only.tar.gz` (current, Merchant paused) | `5821094a72bfbf551cf0ae78e008584f8038adc0f06455c938f9e7a8182470f4` |

Archives are retained under `/opt/abashyaka/releases/` and locally under `dist/deployment-20261120/`. The final configuration archive records the incrementally added provisioning/validation scripts and connector uid setting; documentation updates are separate. No environment file, private key, signing key, database dump with rows, QA database or build cache was transferred. The unchanged historical SQL contains seed statements; these ran only in disposable replay and their rows were not restored to deployment.

## Container inventory — PASS| Requested stage | Final classification ||---|---|| 1 — Preparation verification | PASS || 2 — Package transfer, hashes and extraction | PASS || 3 — Private configuration and credentials | PASS || 4 — Database and storage baseline | PASS || 5 — Backend deployment and validation | PARTIAL: healthy and anonymous checks passed; authenticated workflows/live SSE not exercised || 6 — Admin and Nginx | PASS for internal endpoint/asset/health checks; authenticated browser acceptance outstanding; Merchant web paused by user || 7 — Cloudflare preparation | PARTIAL: local connector configuration/approval plan ready; account inspection and activation not performed || Public activation | BLOCKED pending approval and outstanding active-scope readiness/security gates |

| Container | State / health | Networks | Memory sample | CPU sample |
|---|---|---|---|---|
| `abashyaka-postgres` | running / healthy | data | 75.15 MiB | 1.04% |
| `abashyaka-minio` | running / healthy | data | 111.4 MiB | 0.00% |
| `abashyaka-api` | running / healthy | data, app | 4.883 MiB | 0.00% |
| `abashyaka-admin` | running / healthy | app | 48.35 MiB | 0.02% |
| `abashyaka-merchant` | stopped by request, exit 0 | retained container | — | — |
| `abashyaka-nginx` | running / healthy | app, edge | 4.855 MiB | 0.00% |
| `abashyaka-cloudflared` | deliberately absent / not started | planned edge | — | — |

All five running services have empty host port bindings. Host listeners remain SSH 22 and loopback DNS 53 only. `data` and `app` are internal Docker networks; volumes `abashyaka_postgres` and `abashyaka_minio` persist data. Edge networking has no published ingress. Full image IDs and resource samples are in [the sanitized inventory](evidence-20261120/internal-inventory.json).

Host: four CPUs, 7.1 GiB RAM; final sample 1.0 GiB used and 6.1 GiB available. Swap use 28 KiB of 4 GiB. Root disk: 419 GiB available after builds. Load averages: 0.20 / 0.86 / 1.23. These are idle/smoke samples, not capacity or load-test results. Docker Engine 29.10.0; Compose v5.8.0.

## Images and credentials — PASS for internal configuration

| Component | Pinned image digest |
|---|---|
| PostgreSQL 16/PostGIS | `postgis/postgis@sha256:598aed6d6c562b21e071701e6f8ac3092eece7ae332418347025f9e38bcb351f` |
| Existing-repository MinIO image | `elestio/minio@sha256:25348a257f1ece1b192f25f6cd9854618fa86422ac87b494b5d4e629c556d4bd` |
| Nginx | `nginx@sha256:caf4e1e032a20f9c3c5e28fc7f25ffd768ad8677b4975c54193075997b3a97e3` |
| Inactive cloudflared | `cloudflare/cloudflared@sha256:e613aadbc2d9511785d2e67a86b0c8ac18dd63a3f9af0d06faf04cbfdcb35f2d` |

The current publisher PostGIS guidance identified 16-3.7 as maintained; 16-3.5 was downloaded initially but never deployed. MinIO publisher Docker Hub and Quay pulls failed; the image already used by this repository was selected and tested instead. It contains MinIO `RELEASE.2025-09-07T16-13-09Z`, curl and mc. Its maintenance limitation is a public-release blocker below. No new application dependency was added. API, Admin and Merchant were built sequentially from the cleaned committed source.

Credentials were generated directly on Ubuntu using Python `secrets`, exclusively created at `/opt/abashyaka/secrets/deployment.env`, mode 0600. Values were not displayed, downloaded or committed. The API uses a separate PostgreSQL login (no superuser/create-db/create-role/replication privileges) and a bucket-scoped MinIO account. MinIO root credentials are not passed to API. JWT signing secret is unique. No live provider credentials or tunnel token were provisioned.

## Database and storage — PASS for baseline deployment

- Unchanged numbered migrations 001–043 replayed sequentially in a disposable container with networking disabled and no deployment volume mounts. All 43 source checksums verified after replay.
- Schema-only archive SHA-256: `afcb1e6c7d596e33ce0482ec369dcc5d8a558f624282154dcaa335424ed84f1d`. Replay log, SQL checksums and schema TOC remain under release `evidence/`.
- Restore rehearsal into `abashyaka_restore_check` passed with zero users/businesses/products/orders; the rehearsal database is retained for evidence.
- First deployment restore rolled back atomically because the image pre-created `topology`. The successful retry excluded only the duplicate `CREATE SCHEMA topology` TOC entry and preserved the existing extension. Historical SQL was not changed and no schema/data was dropped.
- Actual deployment: PostgreSQL 16.16 and PostGIS 3.7.0. No shared development or existing production database was accessed.
- The reviewable `deploy/abashyaka/system-reference.sql` inserted eleven discovery categories, two catalog root categories and the two source-defined districts Cuttack/Jajpur. No delivery localities or partner coverage were activated.
- Final counts: users, businesses, products, platform products, orders, delivery localities, financial journals, financial postings, COD collections and payout transfers all **zero**. There is no live/synthetic financial activity to reconcile.
- Buckets `abashyaka-public` and `abashyaka-private` both remain private. The restricted API account passed stat plus unique-object write/read/delete probes in both; no probe objects were retained. API upload through an authenticated user remains untested.

The baseline is tracked by the release SQL checksum manifest and replay log, not by inventing an application migration-history table. Future releases require explicit incremental migration checks. Preserve volumes; never replay the baseline over this deployed schema.

## Executed acceptance checks

| Check | Result |
|---|---|
| Real Compose interpolation and all profiles `config --quiet` | PASS; secret values not printed |
| API/Admin/Merchant sequential Docker builds | PASS |
| Compose `up -d --wait` for database, storage, API, portals and gateway | PASS |
| API `/healthz` directly and through API Host on Nginx | PASS — HTTP 200, `{"status":"ok"}` |
| Discovery categories / catalog locations | PASS — HTTP 200, DB-backed responses |
| Food catalog categories/products with `city=Cuttack` | PASS — HTTP 200; no fabricated products |
| Missing district filter and unsupported Bhubaneswar catalog filter | PASS — HTTP 400 per current source contract |
| Anonymous Merchant businesses/orders, Admin admins, SSE | PASS — HTTP 401 |
| Admin `/admin/login` and Merchant `/` | PASS — HTTP 200 directly and through matching Nginx Host |
| Next.js relative `/api/v1/categories` rewrites in both portals | PASS — HTTP 200 |
| Two JavaScript assets per portal through Nginx | PASS — HTTP 200, including `/merchant/_next/` prefix |
| Unknown Nginx Host | PASS — HTTP 404 |
| `nginx -t` | PASS |
| API startup log scan | PASS — no error/fatal/panic levels or configured secret values |
| Runtime flags and port bindings | PASS — checked from sanitized inspection |
| Python syntax (7 deployment scripts), `git diff --check` | PASS |
| Redis audit | PASS — no application manifest dependency/deployment service; none introduced |
| Authenticated cross-merchant isolation, commerce lifecycle, authorized live SSE | PARTIAL — no deployment users or active normal OTP transport; not claimed tested |
| Android/UI acceptance | Not performed per explicit boundary; no APK rebuilt or changed |

The endpoint probes are service/API acceptance, not authenticated browser workflow or full OpenAPI conformance tests. No comprehensive Go/Flutter suite or load test was run in this deployment checkpoint. Initial smoke-client assumptions about district filters and Node fetch Host handling were corrected to the actual source contract and `http.request`; final checks passed. Initial storage probe cleanup returned a false failure after successful operations; cleanup was fixed and the complete check passed. Re-running one-time MinIO provisioning also failed on an already-provisioned step; credentials/policies were not weakened, and final restricted-account validation passed separately.

## Security and public-release gates

Runtime `APP_ENV=production`, SMS provider `stub`, and explicitly false QA OTP delivery, payment sandbox, synthetic COD, dispatch, earnings simulation/posting and commercial earnings-policy flags were verified. No provider/payment secrets, QA allowlist or writer credentials are present. Authentication remains fail-closed; do not fabricate JWTs or enable QA login in this deployment. Dispatch is deliberately disabled, so no active sweep/assignment acceptance is claimed.

**BLOCKED before any Merchant web reactivation:** read-only `npm audit --omit=dev --json` reports one critical package (`next`) and one high package (`postcss`) in Merchant. The report's suggested automatic repair is a major Next.js upgrade; it was not applied. Admin reports zero production vulnerabilities at the time of audit. These are dependency database findings, not proof that every advisory is exploitable in this configuration. See [Merchant audit](evidence-20261120/merchant-dependency-audit.json) and [Admin audit](evidence-20261120/admin-dependency-audit.json).

The selected legacy MinIO release is unmaintained; the [publisher repository](https://github.com/minio/minio) is archived and no longer maintained. A supported storage maintenance decision is required before public operation. The [PostGIS publisher](https://hub.docker.com/r/postgis/postgis/) documents the maintained tag transition used for this fresh database.

Also outstanding: genuine Admin onboarding and approved normal authentication, authenticated role/isolation/commerce/SSE acceptance, media URL and private-object authorization review, approved locality coverage, backup/restore/off-host backup, host firewall/effective SSH/suspend checks and external-network HTTPS validation. Container health does not satisfy these gates. No real SMS, payment collection, cash handling, transfers or payouts were enabled.

## Cloudflare — configuration prepared, activation awaiting approval

Pinned `cloudflared` 2026.11.1 reports token-file support. No token exists at the planned path; no standard config directories were found at `/etc/cloudflared` or `/home/devserver/.cloudflared`. No Cloudflare account/session inspection was available. Connector absent, DNS unchanged, main domain unchanged.

The inactive Compose `tunnel` profile uses the protected token file and deployment uid/gid 1000, with a healthy-Nginx dependency. Internal Nginx routing is tested for API/Admin Host names; the paused Merchant Host returns 404; media/admin storage routes remain unexposed. See [the approval plan](CLOUDFLARE_APPROVAL_PLAN.md) for proposed origins, Admin Access requirements and dashboard steps. Confirm exact public hostnames/paths before activation. Do not start the connector until the user's approval and security gates are satisfied.

Stop boundary reached: five internal services healthy; Merchant web stopped; public routing/tunnel inactive. Latest checks passed: Merchant hostname HTTP 404, mobile Merchant endpoint on API hostname HTTP 401 without authentication, Admin page and assets HTTP 200. Nginx was recreated to refresh its read-only configuration mount after removing the stopped upstream. The standalone gateway profile was corrected to include its API dependency. Merchant dependency remediation is deferred until web reactivation. Next tasks for the active API/Admin scope are storage-maintenance review, approved normal authentication, authenticated acceptance and public-exposure review.
