# Deployment source package — 20 November 2026

Prepared locally from the existing `D:\grepmind-near` checkout on `abashyaka-dev-02`.

Source commit: `8d5eb0fec1e10417073c01419201ac1859c3e78c`.

| Local archive | SHA-256 |
|---|---|
| `dist/deployment-20261120/abashyaka-base.tar.gz` | `510376ce70dbfe9573687fff37f636834801f62719fff4d3f2a0e9854cdeb490` |
| `dist/deployment-20261120/abashyaka-overlay.tar.gz` | `d7668738ab4d583941485b7d68f44c0e8c038af7526209739918a31e29ff2bcd` |

The base archive uses `git archive HEAD backend apps/admin-web apps/merchant-web`; it excludes uncommitted application work. The overlay contains `deploy/abashyaka` and the two deployment guides plus `COMMAND_RUNNER_DIAGNOSTICS_2026-11-20.md`. This checksum manifest is separate from the archives. Archives are local ignored build artifacts, not a new checkout. Archive listing checks passed: three Dockerfiles, 43 numbered migrations, readable tar files, and no paths matching `.env`, `id_rsa`, `private_key`, `*.pem`, or `*.key`. This path check is not an exhaustive content secret scan. The committed `seed_images.sql` is present in the source archive but must remain excluded from numbered migration replay.

No files have been transferred to Ubuntu. No release has been extracted, no images pulled, and no containers started in this run. Before transfer, complete the operator directory step in [the diagnostic record](COMMAND_RUNNER_DIAGNOSTICS_2026-11-20.md), verify directory ownership and modes, and review the chosen deployment image digests. Transfer these exact archives and compare server SHA-256 values before extraction. Changed source or documentation requires new archives and checksum records.

The next planned release path is `/opt/abashyaka/releases/8d5eb0f-d02`; stop if it already exists. Continue with the existing [Ubuntu guide](Abashyaka-server-deployment-ubuntu.md) and [migration guide](Abashyaka-database-migrations.md). Current status is PARTIAL/BLOCKED on interactive Ubuntu sudo, not SSH connectivity.

## Continuation audit

The original archive hashes above remain unchanged. The continuation audit found tracked QA test artifacts in the base archive and prepared a separately named cleaned archive. No server transfer occurred because the destination directories remain absent. See [the internal deployment attempt](INTERNAL_DEPLOYMENT_ATTEMPT_2026-11-20.md) for the cleaned archive hash, exclusions, current statuses and next operator action. Rebuild and checksum the overlay before transfer because the local deployment documentation has changed.

## Executed internal deployment

The cleaned source and D03 overlay were transferred and verified, then extracted into `/opt/abashyaka/releases/8d5eb0f-d03`. Five services are healthy; Merchant web is paused. The original archive descriptions above are historical checkpoint records. See [the result](INTERNAL_DEPLOYMENT_RESULT_2026-11-20.md) for actual archive hashes, final configuration changes and validation.
