# Cloudflare activation plan — approval required



This is a proposed configuration, not an instruction to publish immediately. Do not start the `tunnel` profile or create DNS/published application routes before the user's explicit public-exposure approval.



Merchant web is paused by user instruction. Mobile Merchant endpoints remain part of `api.abashyaka.com`; no separate Merchant web hostname is requested.



## Proposed origins



| Proposed hostname | Origin from connector | Origin HTTP Host | Additional gate |

|---|---|---|---|

| `api.abashyaka.com` | `http://nginx:80` | `api.abashyaka.com` | Approve initial public paths explicitly; internal Nginx currently routes health and `/api/v1/` |

| `admin.abashyaka.com` | `http://nginx:80` | `admin.abashyaka.com` | Approve hostname and configure Cloudflare Access identity policy before public routing |

| `merchant.abashyaka.com` | Disabled | None | Paused by user; no gateway vhost or tunnel route; remediate dependencies before reactivation |

| `abashyaka.com` | None prepared | None | Main-domain application hosting remains a separate decision; preserve current DNS/mail records |



## Dashboard steps after approval



1. Use the authorized Cloudflare account. Inspect existing tunnels and zone records before creating anything. In Networking > Tunnels, reuse an appropriate existing remotely managed tunnel or create `abashyaka` if none exists.

2. Keep its published application routes absent until the approved exposure scope and Access policy are ready. Adding a published route can immediately expose the application and create its DNS record.

3. Place the tunnel token directly on Ubuntu at `/opt/abashyaka/secrets/tunnel-token`, owned by deployment uid/gid 1000 with mode 0600, within the existing mode-0700 secrets directory. Never paste it into chat, source, command history, or deployment logs. Use an interactive local protected-file entry workflow.

4. The Compose connector is pinned by digest, uses the token-file argument and runs as uid/gid 1000 so it can read that file without broadening permissions. It has no Docker socket or host ports. Confirm the pinned binary supports `--token-file` and test configuration without displaying the token.

5. Create only the approved hostname routes, with origin `http://nginx:80` and the matching Host header. Require Access on Admin; avoid interactive browser challenges on mobile API calls. Keep PostgreSQL, MinIO/API administration and media/KYC routes unexposed.

6. Start only the approved connector after the internal gateway is healthy. Verify connector health, HTTPS from an external network, hostname/path isolation, SSE with authorized normal authentication, and Admin Access enforcement. Stop on any mismatch. Keep SMS, payment collection, QA automation, dispatch and compensation disabled.



Before public activation, resolve the recorded legacy MinIO maintenance limitation, Merchant dependency remediation before any future web reactivation, genuine Admin provisioning/normal authentication, authorized role acceptance, backup/restore and host firewall/suspend review. A healthy container alone does not pass these gates. No Android build is authorized in this checkpoint.



Reference: [Cloudflare dashboard tunnel setup](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/get-started/create-remote-tunnel/).

