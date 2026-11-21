# Internal Ubuntu deployment continuation — 20 November 2026

## Overall result: BLOCKED before transfer

The user authorized internal database, storage, backend, portal and Nginx deployment, with no public exposure, DNS changes, Android rebuild or feature development. The command runner is working. The required Ubuntu directory prerequisite is still absent according to two actual server checks after the continuation request. No installation or deployment success is claimed.

## Step 1: PARTIAL — source and host inspection passed, directory prerequisite failed

| Check | Actual result |
|---|---|
| Checkout | `D:\grepmind-near`, `abashyaka-dev-02`, HEAD `8d5eb0fec1e10417073c01419201ac1859c3e78c` |
| Preserved branch | `git branch -v` shows `abashyaka-dev-01` still at `8d5eb0f`; no branch switch, reset, checkout creation or Git mutation performed |
| Existing mobile work | `order_tracking_screen.dart`: 38 insertions, 16 deletions; `order_history_test.dart`: 90 insertions, 4 deletions; left untouched |
| Mobile file SHA-256 | screen: `03982411e0b4b8b3efe39456230cbba53b68046351a79cb95a3b4f698b0f97ab`; test: `74094f54beab8af07e150d3ff84a68855730b8085fc23ee7ecdbb85104563591` |
| Original source archive | SHA-256 matches checkpoint: `510376ce70dbfe9573687fff37f636834801f62719fff4d3f2a0e9854cdeb490` |
| Original overlay | SHA-256 matches checkpoint: `d7668738ab4d583941485b7d68f44c0e8c038af7526209739918a31e29ff2bcd` |
| Remote identity | `devserver`, uid/gid 1000; primary group `devserver`; Docker group membership present |
| Target directories | `/opt/abashyaka`, `/opt/abashyaka/releases`, `/opt/abashyaka/secrets`: all absent; ownership, permissions and writability cannot pass |
| Privilege | `sudo -n -l`: `sudo: interactive authentication is required`; `/opt` is root:root mode 755 |
| Capacity | 4 CPUs, 7.1 GiB RAM, approximately 533 MiB used, 6.6 GiB available, 4 GiB swap unused; root disk 455 GiB total / 429 GiB available |
| Docker | Engine 29.10.0; Compose v5.8.0 |
| Inventory | No containers, no volumes; default networks `bridge`, `host`, `none` only |
| Redis | PASS: no Redis dependencies in Go or either web portal dependency manifests, and no Redis service in deployment Compose. Local `docker-compose.yml` explicitly says Redis is intentionally excluded. None introduced. |

SSH checks used `BatchMode=yes`, `ConnectTimeout=10`, and supported Windows host command escalation. No SSH keys, host verification settings, sudo policy or host security configuration changed. Some initial file searches used unsupported PowerShell wildcard paths; the Redis dependency search was rerun using ripgrep file globs and completed with exit 1 (no matches), rather than treating those initial errors as evidence.

## Package audit and cleaning: PASS for local artifact preparation

The original committed-source archive contains tracked QA test results, QA runners and fixtures. It was not transferred. A separately named cleaned archive was prepared from it without changing the checkout or either original archive:

`D:\grepmind-near\dist\deployment-20261120\abashyaka-base-clean.tar.gz`

SHA-256: `5cbaf640dcc8411608edcfd5ffe645709749c3ff16f36567ae7fc0b22a7b0195`.

The cleaning excluded 85 entries: e2e/test results, Go test files, QA-only runner/fixture/helper directories, QA Playwright configuration and unnumbered `seed_images.sql`. It retained 248 entries, all three Dockerfiles and all 43 numbered migration files. Assertions rejected unsafe paths, links and credential/dump/signing-key filenames; reopening and checking the resulting archive passed. The local ignored `clean-package-manifest.json` records all exclusions. This is a path/structure check, not an exhaustive source-content secret scan. Retained QA-provider code used by the normal API must stay subject to its production fail-closed gates; it is not a deployed QA service.

Historical numbered migrations contain built-in identities, businesses and products. They remain unchanged. They must be replayed only in the disposable, isolated replay database; only the resulting schema can be restored to the fresh deployment database. Direct execution into the deployment database would introduce unwanted data. This is the already documented schema-only bootstrap, not a new migration history. No replay, restore or reference-data insertion ran during this attempt. Required reference data needs an explicit reviewed list; historical categories alone are not proof that the runtime is ready.

## Remaining stages

| Requested stage | Status | Actual state |
|---|---|---|
| Step 2 — transfer and extract | BLOCKED | Required destination absent. No transfer, remote checksum verification or extraction occurred. Preserve original packages; use the cleaned source and a newly checksummed documentation/config overlay on continuation. |
| Step 3 — credentials and Compose | PARTIAL | Existing configuration inspected; prior placeholder structural check passed. No deployment credentials generated or written; no real environment validation or image digest selection performed. |
| Step 4 — PostgreSQL/PostGIS and MinIO | BLOCKED | No containers/volumes started, migrations executed, buckets initialized or connectivity checks possible. |
| Step 5 — Go backend | BLOCKED | No build/start; API health response, DB/storage connectivity, merchant isolation, catalog/commerce and SSE are untested on this server. |
| Step 6 — portals and Nginx | BLOCKED | No build/start; no healthy portal or gateway claim. Existing Nginx file routes only API liveness and still needs internal portal/API/SSE routing and portal health checks. Merchant asset prefix `/merchant` requires routing verification. |
| Step 7 — Cloudflare | PARTIAL | Existing Compose token-file plan inspected only. No account configuration/token discovered, connector started, dashboard/DNS change made or public application exposed. Approval-ready tunnel acceptance depends on healthy internal services. |

The source configuration disables QA OTP delivery, dispatch, synthetic rider earnings, earnings posting and sandbox COD under `APP_ENV=production`; SMS provider `stub` supplies no real delivery transport outside local mode. Sandbox payment provider selection fails closed outside isolated QA/test. These are source findings, not verified running-container settings. No real SMS/payment configuration was supplied. Authentication acceptance will require an approved normal authentication path; do not bypass it or fabricate JWTs. Background dispatch must remain disabled at this checkpoint.

## Cloudflare requirements for the later approval gate

Inspect the account's existing tunnels and hostname records through an authorized account session. Prepare an inactive remotely managed tunnel, origin `http://nginx:80`, and a protected token file outside source control. Plan `api.abashyaka.com` plus separately approved Admin/Merchant hostnames, preserving Host headers and same-origin `/api/v1` routes. Main `abashyaka.com` has no separately verified application origin in this deployment. Configure Cloudflare Access for Admin before any public Admin route; avoid browser challenges on mobile API traffic. Do not create DNS routes or start the connector until public-exposure approval. Existing records, credentials and public routing were not inspected in this attempt.

## Next operator action

Run in the operator's own PowerShell terminal; enter any sudo password only in that terminal:

```powershell
ssh -t devserver@192.168.1.3 'sudo install -d -m 0750 -o devserver -g devserver /opt/abashyaka/releases && sudo install -d -m 0700 -o devserver -g devserver /opt/abashyaka/secrets'
```

The expected directory ownership/modes are `devserver:devserver 750` for releases and `devserver:devserver 700` for secrets. Confirm the command's successful completion. The account-name reply alone does not prove directory creation; the repeated server check returned absent paths. Do not submit passwords into this chat. Do not use Docker privileges to bypass host directory administration.

Once verified, continue transfer into a new versioned release, real configuration validation, private persistent services, isolated SQL replay/schema restore, sequential builds and internal acceptance. Public activation remains a separate approval boundary. There was no APK work, emulator work, feature implementation, QA database import, credential provisioning or money movement.
