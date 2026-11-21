# Windows command runner and Ubuntu deployment diagnostics

Date: 20 November 2026 (Asia/Calcutta). Application feature development paused.

## Conclusion

The default Windows command sandbox blocks outbound SSH before authentication. The identical requested SSH command succeeds when run with `sandbox_permissions="require_escalated"`. The LAN, server SSH service, existing key, and Docker access work from that host execution context. This is a sandbox network restriction, not an SSH authentication failure. Service enumeration also differs inside the sandbox. The underlying Windows enforcement component was not traced; the paired execution results establish the failing permission boundary.

The existing checkout is `D:\grepmind-near`, branch `abashyaka-dev-02`, commit `8d5eb0fec1e10417073c01419201ac1859c3e78c`. No checkout or branch was created. Existing edits to `order_tracking_screen.dart` and `order_history_test.dart` were preserved.

## Requested commands and actual output

Commands ran through the actual `exec_command` tool in Windows PowerShell. Formatting whitespace is normalized below; result text is preserved. Each command initially ran in the sandbox. Blocked host/network diagnostics were retried with supported elevated execution.

1. `whoami` — exit 0

   ```text
   desktop-0q466gb\srika
   ```

2. `Get-Location` — exit 0

   ```text
   Path
   ----
   D:\grepmind-near
   ```

3. `Get-Command ssh` — exit 0

   ```text
   CommandType Name    Version Source
   ----------- ----    ------- ------
   Application ssh.exe 9.5.6.4 C:\WINDOWS\System32\OpenSSH\ssh.exe
   ```

4. `git worktree list` — exit 0

   ```text
   D:/grepmind-near 8d5eb0f [abashyaka-dev-02]
   ```

5. `git branch --show-current` — exit 0

   ```text
   abashyaka-dev-02
   ```

6. `Get-Service ssh-agent`

   Sandbox, exit 1:

   ```text
   Cannot find any service with service name 'ssh-agent'.
   ```

   Elevated host, exit 0:

   ```text
   Status  Name      DisplayName
   ------  ----      -----------
   Stopped ssh-agent OpenSSH Authentication Agent
   ```

7. `ssh-add -l` — exit 1 in both contexts

   ```text
   Error connecting to agent: No such file or directory
   ```

8. `Test-NetConnection 192.168.1.3 -Port 22` — exit 0 in both contexts; inspect `TcpTestSucceeded`, not just process exit

   Sandbox:

   ```text
   WARNING: TCP connect to (192.168.1.3 : 22) failed
   WARNING: Ping to 192.168.1.3 failed
   Invoke-CimMethod: Access to a CIM resource was not available to the client.
   ComputerName     : 192.168.1.3
   RemoteAddress    : 192.168.1.3
   RemotePort       : 22
   InterfaceAlias   :
   SourceAddress    :
   PingSucceeded    : False
   TcpTestSucceeded : False
   ```

   Elevated host:

   ```text
   ComputerName     : 192.168.1.3
   RemoteAddress    : 192.168.1.3
   RemotePort       : 22
   InterfaceAlias   : Wi-Fi
   SourceAddress    : 192.168.1.2
   TcpTestSucceeded : True
   ```

9. `ssh -o BatchMode=yes -o ConnectTimeout=10 devserver@192.168.1.3 "hostname; whoami; docker ps"`

   Sandbox, exit 1 as reported by the command tool:

   ```text
   ssh: connect to host 192.168.1.3 port 22: Permission denied
   ```

   Elevated host, exit 0:

   ```text
   devserver
   devserver
   CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES
   ```

## Credential and environment distinction

A filtered `ssh -v ... "true"` check confirmed:

```text
Authenticated to 192.168.1.3 ([192.168.1.3]:22) using "publickey".
```

OpenSSH offered and the server accepted the existing `C:\Users\srika\.ssh\id_rsa`. No key contents were read or displayed. Elevated host credential access is proven; sandbox key access was not established because the connection fails earlier. The agent is stopped and unnecessary for this observed file-key login. No agent, key, SSH configuration, host verification, or server security setting was changed.

The executor is PowerShell Core 7.6.9, `Win32NT`, Microsoft Windows 10.0.26300, using Windows OpenSSH 9.5.6.4. These commands did not run in WSL. The remote commands run on Ubuntu 26.04.1 LTS, Linux 7.0.0-44-generic, x86_64. No WSL diagnosis is inferred from these results.

## Required permissions and permanent setup

Keep workspace write access for `D:\grepmind-near` and an approval policy permitting sandbox escalation. Use `require_escalated` for authorized host SSH commands in the current restricted-network session. The runtime has accepted escalation and saved several exact read-only command rules. Reuse those rules; do not repeat a sandbox probe or approval for the identical permitted command. Different commands can still require approval. Host execution escalation is separate from Windows Administrator elevation and remote Ubuntu sudo.

Recommended setup: keep the Windows host executor under the existing user, keep this checkout as the working directory, use Windows OpenSSH with the existing key and known-host verification, and retain narrowly scoped saved diagnostic approvals. Avoid blanket `ssh` approvals: the remote command argument can perform arbitrary mutations. Keep deployment mutation approvals separate. Do not change to WSL merely to fix this issue.

For a user-managed Codex configuration, the documented baseline is:

```toml
sandbox_mode = "workspace-write"
approval_policy = "on-request"
```

Managed policy must allow sandbox approval requests (if granular policy is used, `sandbox_approval` must be enabled). This session already supports the necessary requests. No configuration file was modified. Unrestricted network access or bypassing the sandbox is unnecessary for the demonstrated working path. Managed permission profiles can override local settings; the commands above, rather than a proposed setting, are the evidence of current access.

References: [Windows sandbox](https://learn.chatgpt.com/docs/windows/windows-sandbox) and [Agent approvals and security](https://learn.chatgpt.com/docs/agent-approvals-security).

## Deployment continuation and actual gates

Read-only server preflight succeeded through SSH:

- Ubuntu 26.04.1 LTS, four CPUs, 7.1 GiB RAM, 4 GiB swap, 429 GiB free root disk.
- Docker Engine 29.10.0; Compose v5.8.0; no containers (including stopped containers), no Docker volumes, only default networks.
- TCP SSH listener on port 22; NTP synchronized.
- `systemd-analyze cat-config systemd/logind.conf` showed commented default lid/suspend options and one vendor inhibit-delay drop-in; actual lid behavior remains unverified.
- `sudo -n -l` returned `sudo: interactive authentication is required`.
- `/opt/abashyaka`, `/opt/abashyaka/releases`, and `/opt/abashyaka/secrets` do not exist. A subsequent read-only check confirmed this; group `devserver` exists as the user's primary group. Directory readiness check exited 1.
- The existing migration replay script passed remote `bash -n` (exit 0); the script was not executed.
- The existing Compose file passed remote `docker compose --project-directory /tmp -f - --profile api --profile portals --profile tunnel config --quiet` with explicit `validation-only` image/credential placeholders (exit 0). This checks syntax/interpolation, not real secrets, image existence, builds, or service health. Neither check wrote server files or started containers.

**D03 remains PARTIAL/BLOCKED at privileged host preparation.** The operator must run the following in their own interactive terminal, entering any sudo password only there:

```powershell
ssh -t devserver@192.168.1.3 'sudo install -d -m 0750 -o devserver -g devserver /opt/abashyaka/releases && sudo install -d -m 0700 -o devserver -g devserver /opt/abashyaka/secrets'
```

Then verify ownership/modes and writable directories over SSH, transfer and checksum the prepared source, review image digests, and proceed with isolated migration replay and schema-only restore according to the existing guides. Do not route around sudo using Docker host mounts or privileged containers. Firewall and effective SSH checks also still need an authorized privileged operator. No shared/production migration, deployment activation, tunnel/DNS change, APK build, credential provisioning, or money movement occurred in this diagnostic run. Mobile acceptance is not claimed.

## Subsequent outcome

The operator completed directory setup; SSH verification passed. Internal deployment subsequently completed for PostgreSQL, MinIO, API, Admin and Nginx. Merchant web was stopped at the user's instruction. See [the deployment result](INTERNAL_DEPLOYMENT_RESULT_2026-11-20.md); the prior sudo/directory block above is historical.
