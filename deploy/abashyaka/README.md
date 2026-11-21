# Abashyaka deployment configuration

The deployment configuration prepares the Ubuntu Compose project from commit `8d5eb0f` on the active `abashyaka-dev-02` checkout. The deployment root is `/opt/abashyaka`. Use a private environment file and tunnel token outside the source checkout with restricted permissions. The PostgreSQL and MinIO application accounts must differ from their administrative accounts. Build the three local application images sequentially on the four-core host.

From the repository root, validate the configuration without printing interpolated secrets:

```sh
docker compose --env-file /opt/abashyaka/secrets/deployment.env \
  -f deploy/abashyaka/compose.yaml --profile api --profile portals --profile tunnel config --quiet
```

| Gate | Required work |
|---|---|
| D03 | Validate linux/amd64 image digests and confirm PostgreSQL 16, PostGIS, and each image's healthcheck tooling. Provision restricted database and object storage accounts. Rehearse and approve the schema bootstrap before starting the API profile. Verify storage and database connectivity separately from the API's liveness endpoint. |
| D04 | Verify both portal builds and their internal same-origin API routing. Implement and validate approved gateway routes for Admin, Merchant, media, and SSE with correct path handling. |
| D05 | Complete firewall, SSH, and suspend checks. Configure Cloudflare Access before routing the Admin hostname. Approve external DNS and tunnel changes separately. The gateway is internal only; API/Admin routes are configured, Merchant web is paused, and no public routes are authorized. |
| D06–D08 | After HTTPS works, configure Android and validate the release build. Establish database and object storage backup, restore drills, and rollback before live commerce. |

## Schema and storage gates

The deployment includes migrations 001–043. Earlier SQL embeds development records and dependencies. Use the [migration guide](../../docs/deployment/Abashyaka-database-migrations.md) to replay all migrations in isolation and restore only the schema. Never mount these migrations as automatic PostgreSQL initialization scripts or run the QA migration script against this deployment. Use the [Ubuntu deployment guide](../../docs/deployment/Abashyaka-server-deployment-ubuntu.md) for source transfer, configuration, and acceptance.

Prepare public and private MinIO buckets with separate policies, and issue a restricted API credential. The baseline upload service emits localhost URLs and still needs reviewed public URL and private object handling before exposing media traffic.

The API and portals have no published host ports. Keep the tunnel profile off until D05. SMS, synthetic COD, QA OTP delivery, and dispatch remain disabled for this initial configuration. Use a remotely managed tunnel and cloudflared 2025.4.0 or later for token-file support. Set the origin to `http://nginx:80` and preserve the `api.abashyaka.com` Host header. The token file must be readable by the selected container user without opening host permissions broadly. Record selected image digests, applied migrations and results in the deployment log.

## Current internal deployment

See [the executed report](../../docs/deployment/INTERNAL_DEPLOYMENT_RESULT_2026-11-20.md). Use profiles `api`, `portals` (Admin only), and `gateway` for active internal services. Merchant web is stopped and isolated in the opt-in `merchant` profile; do not enable it during the pause. Mobile Merchant backend endpoints are preserved. The `tunnel` profile remains inactive pending approval. Provisioning Python scripts are one-time bootstrap tools for a new empty deployment; validation scripts are separate and must not fabricate authentication. Credentials stay in the protected Ubuntu secrets directory.
