# Abashyaka server deployment on Ubuntu

**Current status (20 November 2026): PARTIAL acceptance.** PostgreSQL/PostGIS, MinIO, API, Admin and Nginx are deployed and healthy internally at `/opt/abashyaka/releases/8d5eb0f-d03`. Merchant web is stopped by user request; its gateway route is removed. Mobile Merchant APIs remain running. Cloudflare and public routing remain inactive. See [the executed deployment report](INTERNAL_DEPLOYMENT_RESULT_2026-11-20.md), [current inventory](evidence-20261120/internal-inventory.json) and [Cloudflare approval plan](CLOUDFLARE_APPROVAL_PLAN.md). Prior directory/connectivity blockers below are historical and resolved.

## Historical execution record (superseded where noted above)

| Environment | Command or check | Observed result |
|---|---|---|
| Windows PowerShell, operator transcript | ssh devserver@192.168.1.3 | Successful login to devserver |
| Ubuntu, operator transcript | hostname; uname -m; nproc; free -h; df -h | Ubuntu 26.04.1 LTS, x86_64, 4 logical CPUs, 7.1 GiB RAM, 4 GiB unused swap, 429 GiB free disk |
| Ubuntu, operator transcript | docker version; docker compose version; docker ps; docker network ls; docker volume ls | Engine 29.10.0, Compose 5.8.0, default networks, no running containers or listed volumes |
| Ubuntu, operator transcript | ss -lntu; getent ahosts registry-1.docker.io; curl https://registry-1.docker.io/v2/ | SSH on port 22, registry DNS resolution and HTTPS 401 |
| Ubuntu, operator transcript | timedatectl status; sudo -n ufw status; sudo -n sshd -T; systemd-analyze cat-config systemd/logind.conf | NTP active and synchronized. Privileged checks and effective suspend behavior unverified. |
| Local checkout | git status --short --branch; git rev-parse HEAD | abashyaka-dev-02 based at e9aa875. Original abashyaka-dev-01 retains its working changes. |
| Local Git | git worktree add; git bundle create; git bundle unbundle; git switch -c | The linked worktree failed with a ref-write permission error. The isolated checkout was created using a local Git bundle. |
| Local configuration | Python/PyYAML structural assertions and binary comparisons against git show | Compose structure checked locally. Migrations 041–043 were added byte-for-byte from 8d5eb0f. |
| Codex Windows command runner | whoami; Get-Location; Get-Command ssh; git worktree list; git branch --show-current | Windows account desktop-0q466gb\\srika, PowerShell Core, Windows OpenSSH 9.5. The original checkout is on abashyaka-dev-01. The isolated deployment checkout remains on abashyaka-dev-02 at e9aa875. |
| Codex Windows command runner | Get-Service ssh-agent; ssh-add -l | The service was unavailable to the runner and the agent endpoint was absent. SSH key access and authentication remain untested. |
| Codex Windows command runner | Test-NetConnection 192.168.1.3 -Port 22; ssh -v -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=yes -o UpdateHostKeys=no devserver@192.168.1.3 "hostname; whoami; docker ps" | TcpTestSucceeded=False. OpenSSH returned Permission denied during TCP connect, before authentication, exit 255. Windows PowerShell reached the same host in the operator transcript. |
| Codex elevated retry | Requested one read-only SSH command with sandbox escalation | Automatically rejected. The managed session has sandbox_approval disabled. No remote inspection command ran through Codex. |
| Active deployment checkout | git branch --show-current; git log -1 --oneline; git status --short | D:\grepmind-near is on abashyaka-dev-02 at 8d5eb0f. Deployment files were copied from the earlier temporary checkout. Existing application edits were preserved. |
| Active checkout SSH check | ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=yes -o UpdateHostKeys=no devserver@192.168.1.3 "hostname; whoami; docker ps" | Still fails during TCP connect with Permission denied, exit 255. No server configuration was executed. |

The earlier approval rejection and connection failures above are historical; the current host execution path is verified in the linked diagnostic record. For automated deployment, use an authorized executor with access to the existing deployment checkout and either scoped outbound SSH to the server or local command execution on Ubuntu. Keep SSH host verification enabled and use the existing approved identity. Verify the read-only remote command before starting the planned deployment steps below.

## 1. Host and source preparation

Use the already installed Docker Engine and Compose v5.8.0. For a future fresh host, use Docker's Ubuntu apt repository instructions and install the Engine, CLI, containerd, Buildx, and Compose plugin. Check the target release and architecture against the official support list before adding a repository.

~~~bash
docker version
docker compose version
sudo systemctl enable --now docker
sudo ufw status verbose
sudo sshd -T | grep -E '^(permitrootlogin|passwordauthentication|pubkeyauthentication) '
timedatectl status
systemd-analyze cat-config systemd/logind.conf
sudo install -d -m 0750 -o devserver -g "$(id -gn devserver)" /opt/abashyaka/releases
sudo install -d -m 0700 -o devserver -g "$(id -gn devserver)" /opt/abashyaka/secrets
~~~

Verify lid-close and idle behavior locally before exposing a hostname. Keep SSH restricted to the intended management network and retain the working session during any firewall adjustment.

Transfer the reviewed source and deployment files using Windows PowerShell from D:\grepmind-near on abashyaka-dev-02. The base archive selects the three committed build contexts, including migrations 001–043. The overlay adds the two guides and deployment configuration.

~~~powershell
git status --short --branch
git archive --format=tar.gz -o abashyaka-base.tar.gz HEAD backend apps/admin-web apps/merchant-web
tar.exe -czf abashyaka-overlay.tar.gz deploy/abashyaka docs/deployment/Abashyaka-database-migrations.md docs/deployment/Abashyaka-server-deployment-ubuntu.md
Get-FileHash abashyaka-base.tar.gz, abashyaka-overlay.tar.gz -Algorithm SHA256
scp abashyaka-base.tar.gz abashyaka-overlay.tar.gz devserver@192.168.1.3:
~~~

On Ubuntu, compare both hashes before extracting into a new release directory. Each later release gets a new directory and checksum record.

~~~bash
sha256sum "$HOME/abashyaka-base.tar.gz" "$HOME/abashyaka-overlay.tar.gz"
release=/opt/abashyaka/releases/8d5eb0f-d02
mkdir "$release" &&
  tar -xzf "$HOME/abashyaka-base.tar.gz" -C "$release" &&
  tar -xzf "$HOME/abashyaka-overlay.tar.gz" -C "$release"
cd "$release"
~~~

## 2. Configuration and database

Create the environment file once with restricted permissions. Fill it with unique generated secrets and reviewed linux/amd64 image digests. Do not share rendered Compose config, container inspection output containing environment variables, or tunnel credentials.

~~~bash
umask 077
test ! -e /opt/abashyaka/secrets/deployment.env &&
  install -m 0600 deploy/abashyaka/.env.example /opt/abashyaka/secrets/deployment.env
dc() { docker compose --env-file /opt/abashyaka/secrets/deployment.env -f deploy/abashyaka/compose.yaml "$@"; }
dc --profile api --profile portals --profile tunnel config --quiet
dc up -d --wait postgres minio
dc ps
~~~

Follow [Abashyaka-database-migrations.md](Abashyaka-database-migrations.md) for the isolated replay, schema restore, data verification, and application role. Keep the deployment database private. Confirm the selected PostGIS image contains both PostgreSQL 16 and the required PostGIS extension.

Provision MinIO's abashyaka-public and abashyaka-private buckets using a reviewed MinIO client or existing administrative tooling on the private Docker network. Create a distinct service credential from the root credential and scope it to those buckets and the API's required operations. Keep both buckets private for initial validation. Approve catalog-media reads separately and retain private KYC access restrictions. Record bucket and policy names without secret values. The source emits localhost media URLs, so validate public HTTPS URL generation and private object authorization before adding media ingress.

## 3. API and portal acceptance

After completing role, schema, and storage checks, build the API and portals sequentially. Compose currently starts only Postgres and MinIO by default. It binds no host ports.

~~~bash
dc --profile api build api
dc --profile api up -d --wait api
dc --profile api exec -T api wget -qO- http://localhost:8080/healthz
dc --profile portals build admin
# Merchant web is paused; do not build/start it without a new instruction.
dc --profile portals up -d --wait admin
dc --profile portals exec -T admin wget -qO /dev/null http://localhost:3000/admin/login
# Merchant web validation deferred while paused.
dc --profile portals ps
~~~

Health checks establish liveness. Verify DB access, approved reference data, object storage, auth and role isolation separately. Browser APIs should use relative /api/v1. Verify the Admin /admin base path, Merchant root, and Next.js rewrites. Adapt and test Nginx portal, media, and SSE routes before enabling them. Preserve the Go streaming timeout behavior and disabled proxy buffering for SSE.

## 4. Future tunnel and external check — explicit approval required

Use a remotely managed Cloudflare Tunnel with account access over the existing official console. Preserve current DNS and mail records. Configure only the approved initial hostname api.abashyaka.com to origin http://nginx:80, preserving the public Host header. Store the token in the configured file outside Git with permissions compatible with the container user. The internal gateway routes API and Admin; Merchant web is paused. No route is publicly exposed. Confirm the approved public path scope before starting the connector. Set up Cloudflare Access before enabling an Admin route, and keep mobile API traffic free of interactive browser challenges.

~~~bash
dc --profile tunnel run --rm --no-deps nginx nginx -t
dc --profile tunnel up -d --wait nginx cloudflared
dc --profile tunnel ps
curl -fsS https://api.abashyaka.com/healthz
~~~

Run the HTTPS probe from an external network as well. Verify other paths are blocked until approved. Keep QA authentication, customer SMS, live payments, and public commerce disabled. Check container logs locally and redact credentials before sharing.

## 5. Android, backup, updates, and rollback

- After the remote API and app routes work over HTTPS, configure Android with API_BASE_URL=https://api.abashyaka.com. The Flutter client appends /api/v1 itself. Verify media and SSE URLs, release signing, QA automation disabled, package ID unchanged, and no cleartext in the public build. Record APK version, signing status, hash, and emulator/physical-device acceptance.
- Before launch, back up PostgreSQL with pg_dump custom format and copy MinIO objects with approved tooling. Keep encrypted copies off-host. Keep schema checksums, image digests, release archives, and Compose config separate from credentials. Conduct a restore drill into a separate database and bucket set.
- For updates, build from a new release directory and keep the previous images by digest. Validate configuration, schema compatibility, and service health before switching releases. For rollback, use the previous compatible image and configuration. A database restore requires separate restore validation and cutover planning. Preserve the persistent Docker volumes.
- Address firewall/SSH/suspend checks, fixture-free reference data, Admin Access, portal ingress, external HTTPS/SSE, Android signing, and full-order acceptance before launch. Resource headroom indicates suitability for initial validation. Record actual CPU, memory, and disk usage during sequential builds and representative traffic.

[Docker Engine installation for Ubuntu](https://docs.docker.com/engine/install/ubuntu/) · [Cloudflare Tunnel run parameters](https://developers.cloudflare.com/tunnel/reference/run-parameters/)
