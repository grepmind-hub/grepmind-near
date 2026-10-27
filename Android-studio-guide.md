# Local Development Guide: WSL2 Flutter + Windows Android Emulator

Last verified: 2026-10-27

Scope: Ubuntu on WSL2, Flutter running inside WSL, Android emulator running on Windows, ADB bridged over TCP.

This guide covers the daily start/stop workflow, the architecture behind it, and recovery steps for the problems already encountered in this environment.

## 1. What this setup does

The Android emulator is a Windows application, but Flutter and Gradle run inside WSL. The two sides communicate through the Windows ADB server.

```text
+--------------------------- Windows host ----------------------------+
|                                                                     |
|  Android emulator (Medium_Phone_API_37.0)                           |
|          |                                                          |
|          | USB-like ADB connection on 127.0.0.1:5037                |
|          v                                                          |
|  adb.exe server  -->  listens on 0.0.0.0:5037                       |
|                              ^                                      |
+------------------------------|--------------------------------------+
                               | TCP
                               | WSL2 NAT gateway: <gateway>:5037
+------------------------------|--------------------------------------+
| WSL2 Ubuntu                  |                                      |
|                              |                                      |
|  Linux adb client -----------+                                      |
|  ADB_SERVER_SOCKET=tcp:<gateway>:5037                               |
|                                                                     |
|  Flutter -> Linux Android SDK -> Gradle -> APK -> adb install       |
+---------------------------------------------------------------------+
```

### Why there are two Android SDKs

| SDK | Location | Used for |
|---|---|---|
| Linux SDK | `/home/grepmind/Android/Sdk` | Flutter, Gradle, `aapt`, `aapt2`, `zipalign`, Linux `adb` client, APK builds |
| Windows SDK | `D:\emulator\android-sdk` | Windows `adb.exe` server, `emulator.exe`, AVDs, emulator images |

Do not point WSL `ANDROID_HOME` at the Windows SDK. The Windows SDK contains `aapt.exe` and `adb.exe` but no Linux executables, so Flutter on Linux cannot build with it.

`ADB_SERVER_SOCKET` is what lets the Linux `adb` client use the Windows ADB server instead of starting a second server inside WSL.

## 2. Verified environment

| Item | Value |
|---|---|
| WSL version | WSL2, NAT networking |
| Ubuntu | 24.04.5 LTS |
| Flutter | 3.47.8 stable |
| Dart | 3.13.7 |
| Java | OpenJDK 17.0.20.1 |
| Linux Android SDK | `/home/grepmind/Android/Sdk` |
| Linux platform | `android-36` |
| Linux build-tools | `36.0.0` |
| Windows Android SDK | `D:\emulator\android-sdk` |
| Windows AVD | `Medium_Phone_API_37.0` |
| ADB version, both sides | `37.0.1-15733141` |
| Windows ADB listener | `0.0.0.0:5037` |
| WSL ADB socket | `tcp:<WSL default gateway>:5037` |
| WSL DNS address | `10.255.255.254` (not the Windows host) |

## 3. One-time WSL configuration

The persistent configuration lives in `~/.bashrc`:

```bash
# Flutter + Linux Android SDK for building; Windows ADB server for devices.
export PATH="$HOME/projects/flutter-setup/develop/flutter/bin:$PATH"
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
export ADB_SERVER_SOCKET="tcp:$(ip route show default | awk '/^default/ {print $3; exit}'):5037"
```

Important:

- `ADB_SERVER_SOCKET` must use the WSL default gateway, not `10.255.255.254`.
- `10.255.255.254` is WSL's internal DNS/loopback alias. Connecting ADB to it produces `Connection refused`.
- `~/.profile` must not redefine `ANDROID_HOME`. Verify:

```bash
grep -nE 'ANDROID|ADB' ~/.bashrc ~/.profile
```

Only `~/.bashrc` should define the SDK and ADB variables.

Apply the configuration to an existing terminal:

```bash
source ~/.bashrc
```

A newly opened WSL terminal applies it automatically.

### Linux Android SDK packages

The Linux SDK was installed with these packages:

```bash
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

yes | sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"
```

The Linux command-line tools are installed at:

```text
/home/grepmind/Android/Sdk/cmdline-tools/latest/bin/sdkmanager
```

If the Linux SDK is lost, rebuild it from scratch:

```bash
cd /tmp
curl -fLO https://dl.google.com/android/repository/commandlinetools-linux-13114758_latest.zip
unzip -q commandlinetools-linux-13114758_latest.zip
mkdir -p "$HOME/Android/Sdk/cmdline-tools"
rm -rf "$HOME/Android/Sdk/cmdline-tools/latest"
mv cmdline-tools "$HOME/Android/Sdk/cmdline-tools/latest"

export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

yes | sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"
flutter doctor --android-licenses
flutter doctor -v
```

The command-line tools URL is the version verified for this setup. If Google has published a newer package, use the current Linux command-line tools download instead. Do not install the Windows command-line tools zip into the Linux SDK.

## 4. Daily start procedure

### Step 1 - Start the Windows ADB bridge

Open **Windows PowerShell**:

```powershell
cd D:\emulator\android-sdk\platform-tools
.\adb.exe kill-server
.\adb.exe -a start-server
```

`-a` is required. Without it, ADB listens only on `127.0.0.1` and WSL cannot reach it. `start-server` returns after starting the background daemon.

This only needs to be done after a Windows reboot, after ADB was stopped, or after Android Studio started ADB in localhost-only mode. If port 5037 is already listening on `0.0.0.0`, this is not necessary.

Check:

```powershell
netstat -ano | findstr :5037
```

Expected:

```text
TCP    0.0.0.0:5037    0.0.0.0:0    LISTENING    <pid>
```

If the result is `127.0.0.1:5037`, WSL will not connect. Run `adb kill-server` and `adb -a start-server` again.

Optional: start ADB automatically at Windows login. Create this file:

```text
C:\Users\srika\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\adb-bridge.cmd
```

With this content:

```bat
@echo off
"D:\emulator\android-sdk\platform-tools\adb.exe" -a start-server
```

The command starts the daemon and exits, so it does not leave a console window open. Android Studio and the emulator will reuse the existing server.

### Step 2 - Start the Windows emulator

Choose one method.

**Method A - Android Studio (recommended):**

1. Open Android Studio on Windows.
2. Open **Device Manager**.
3. Select `Medium_Phone_API_37.0`.
4. Click **Play**.
5. Wait until Android finishes booting.

**Method B - Windows PowerShell:**

```powershell
& "D:\emulator\android-sdk\emulator\emulator.exe" -avd Medium_Phone_API_37.0
```

**Method C - From a WSL terminal:**

```bash
/mnt/c/Windows/System32/cmd.exe /c start "" "D:\emulator\android-sdk\emulator\emulator.exe" -avd Medium_Phone_API_37.0
```

Alternatively, run the Windows emulator directly from WSL in a dedicated terminal:

```bash
cd /mnt/d/emulator/android-sdk/emulator
./emulator.exe -avd Medium_Phone_API_37.0
```

The emulator still runs as a Windows application and opens its window on the Windows desktop. WSL is only launching it.

Do not try to use `flutter emulators --launch` to start a Windows AVD. Flutter inside WSL looks for a Linux `emulator` binary. Launch the Windows emulator with one of the methods above instead.

### Step 3 - Verify the ADB bridge from WSL

Open a new WSL terminal, or run `source ~/.bashrc` in the current one:

```bash
echo "$ANDROID_HOME"
echo "$ADB_SERVER_SOCKET"
command -v adb
adb version
adb devices -l
```

Expected values:

```text
/home/grepmind/Android/Sdk
tcp:<gateway-ip>:5037
/home/grepmind/Android/Sdk/platform-tools/adb
Android Debug Bridge version 1.0.41
emulator-5554    device    product:sdk_gphone64_x86_64 ...
```

The device state must be `device`. If it is `offline` or `unauthorized`, see the troubleshooting section.

Windows-side verification:

```powershell
D:\emulator\android-sdk\platform-tools\adb.exe devices -l
```

Both sides should see the same emulator.

### Step 4 - Verify Flutter sees the emulator

```bash
flutter devices
```

Expected when the emulator is running:

```text
sdk gphone64 x86 64 (mobile) • emulator-5554 • android-x64 • Android 17 (API 37) (emulator)
Linux (desktop)              • linux         • linux-x64   • ...
```

If the emulator is missing, run `flutter doctor -v` and see the troubleshooting section.

### Step 5 - Run a Flutter app

```bash
cd ~/projects/my_flutter_app
flutter pub get
flutter run -d emulator-5554
```

If only one Android device is connected, `flutter run` is enough.

For best build performance, keep Flutter projects on the Linux filesystem, for example `~/projects/...`. Projects under `/mnt/c` or `/mnt/d` are slower because they cross the Windows filesystem boundary.

### Hot reload and hot restart

While `flutter run` is attached:

| Key | Action |
|---|---|
| `r` | Hot reload |
| `R` | Hot restart |
| `q` | Quit the app and detach |

## 5. Stop procedure

### Stop the app

In the terminal running `flutter run`, press `q`.

If the terminal is stuck, press `Ctrl+C`.

### Stop the emulator

Choose one method.

**Method A - Close the emulator window.** This is the simplest and safest method.

**Method B - Windows PowerShell:**

```powershell
& "D:\emulator\android-sdk\platform-tools\adb.exe" -s emulator-5554 emu kill
```

Use the Windows `adb.exe` here. The Linux `adb emu kill` command may try to reach the emulator console on the WSL side and can fail with `could not connect to TCP port 5554`.

**Method C - WSL fallback:**

```bash
/mnt/c/Windows/System32/taskkill.exe /IM emulator.exe /F /T
```

This force-closes all Windows emulator processes. Use it only if the normal shutdown methods fail.

### Stop the ADB server (optional)

```powershell
cd D:\emulator\android-sdk\platform-tools
.\adb.exe kill-server
```

Stopping ADB is usually unnecessary. If you stop it, WSL commands will fail with `Connection refused` until you run `adb -a start-server` again.

### Stop WSL (optional)

Close the WSL terminals. If you need to restart the WSL network stack from Windows:

```powershell
wsl --shutdown
```

Warning: `wsl --shutdown` stops all WSL distributions and any Docker containers running inside them. For this project, that includes the Docker Compose stack.

## 6. How the full flow works

1. The Windows emulator starts and registers itself with the ADB server on the Windows machine.
2. The Windows ADB server listens on `0.0.0.0:5037` because it was started with `-a`.
3. WSL cannot use the Windows `127.0.0.1`; WSL2 has its own network namespace. WSL reaches the Windows host through its default gateway.
4. `ADB_SERVER_SOCKET=tcp:<gateway>:5037` tells the Linux `adb` client to connect to the Windows server.
5. `adb devices` from WSL asks the Windows server for its device list and receives `emulator-5554`.
6. Flutter uses the Linux SDK's `adb` client to talk to the Windows server. Because the socket is remote, the Linux client does not start its own local ADB server.
7. Gradle builds the APK with the Linux SDK's `aapt`, `aapt2`, `d8`, and `zipalign`.
8. Flutter sends the APK to the Windows emulator through the bridged ADB connection.
9. Hot reload and debugging traffic continue over the same ADB bridge.

The two SDKs are intentional:

- The Linux SDK is required for compiling Android code inside WSL.
- The Windows SDK is required for the Windows emulator and the Windows ADB server.

## 7. Troubleshooting

### 7.1 Quick diagnosis matrix

| Symptom | Most likely cause | Fix |
|---|---|---|
| `failed to connect to '10.255.255.254:5037'` | WSL is pointed at its own DNS loopback instead of the Windows host | Open a new terminal or `source ~/.bashrc`; verify `ADB_SERVER_SOCKET` uses the default gateway |
| `cannot start server on remote host` | Windows ADB server is not running, or is bound only to `127.0.0.1` | Run `adb kill-server` and `adb -a start-server` on Windows |
| `Connection refused` from WSL | No Windows listener on `0.0.0.0:5037`, wrong gateway, or firewall | Check `netstat`, restart ADB with `-a`, check the firewall rule |
| `error: 10048` on Windows | Port 5037 is already held by an existing ADB server | Do not start a second server; find and stop the existing process, then restart with `-a` |
| `adb devices` shows nothing in WSL | Emulator not running, ADB server not broadcast, or stale env | Start emulator, restart ADB bridge, reopen WSL terminal |
| `flutter devices` shows only Linux | Flutter cannot see the emulator | Run `adb devices`, then `flutter doctor -v` |
| `Android SDK file not found: .../aapt` | `ANDROID_HOME` points to the Windows SDK | Point it to `/home/grepmind/Android/Sdk` and install Linux build-tools |
| Multiple adb binaries warning | Ubuntu `adb` package and SDK `adb` are both installed | Harmless if the SDK path wins; optionally remove the Ubuntu package |
| ADB version mismatch | Linux and Windows platform-tools differ | Update both to the same version, then restart the Windows server |
| Emulator `offline` / `unauthorized` | Stale ADB connection or incomplete boot | Wait for boot, run `adb reconnect`, or restart the ADB server |

### 7.2 `10.255.255.254:5037` connection refused

This was the original failure. `10.255.255.254` is the address WSL uses for its internal DNS proxy; it is not the Windows host.

Check the real Windows host address:

```bash
ip route show default | awk '/^default/ {print $3; exit}'
```

Check the current value:

```bash
echo "$ADB_SERVER_SOCKET"
```

Correct form:

```text
tcp:172.18.160.1:5037
```

The gateway IP can change after WSL restarts. The value must come from the default gateway, which is why `~/.bashrc` calculates it dynamically.

Fix:

```bash
source ~/.bashrc
echo "$ADB_SERVER_SOCKET"
adb devices -l
```

If the value is still wrong, inspect the shell files:

```bash
grep -nE 'ANDROID|ADB' ~/.bashrc ~/.profile
```

Remove any old hard-coded `10.255.255.254` or deleted `~/Android/Sdk` entries from `~/.profile`.

### 7.3 Windows ADB is missing or localhost-only

From WSL:

```bash
/mnt/c/Windows/System32/netstat.exe -ano | grep ':5037'
```

Healthy:

```text
TCP    0.0.0.0:5037    0.0.0.0:0    LISTENING    <pid>
```

Broken (WSL cannot reach it):

```text
TCP    127.0.0.1:5037    0.0.0.0:0    LISTENING    <pid>
```

From Windows PowerShell:

```powershell
cd D:\emulator\android-sdk\platform-tools
.\adb.exe kill-server
.\adb.exe -a start-server
.\adb.exe devices -l
```

Then from WSL:

```bash
adb devices -l
```

If Android Studio is open and immediately restarts ADB in localhost-only mode, close Android Studio, restart ADB with `-a start-server`, then reopen Android Studio. It will reuse the existing broadcast server.

### 7.4 Windows `error: 10048`

`10048` means the socket address is already in use. It does not mean the port is blocked by a firewall.

Find the owner:

```powershell
netstat -ano | findstr :5037
tasklist /FI "IMAGENAME eq adb.exe"
```

If an existing ADB server is healthy and listening on `0.0.0.0`, do nothing. If it is stale or listening only on `127.0.0.1`, stop it:

```powershell
taskkill /F /IM adb.exe
```

Then start one server:

```powershell
cd D:\emulator\android-sdk\platform-tools
.\adb.exe -a start-server
```

This is why `adb -a nodaemon server start` returned `10048`: a server was already bound to 5037. The correct recovery is `kill-server` followed by exactly one `-a start-server`, not starting a second daemon.

### 7.5 WSL sees no emulator, but Windows does

Check Windows first:

```powershell
D:\emulator\android-sdk\platform-tools\adb.exe devices -l
```

If Windows shows `emulator-5554    device`, check WSL:

```bash
echo "$ADB_SERVER_SOCKET"
adb devices -l
```

If WSL still shows nothing:

```bash
adb reconnect
adb devices -l
```

If that fails, restart the Windows ADB server and reconnect the emulator:

```powershell
D:\emulator\android-sdk\platform-tools\adb.exe kill-server
D:\emulator\android-sdk\platform-tools\adb.exe -a start-server
```

The emulator may need a few seconds to re-register. If it does not, restart the emulator.

### 7.6 `flutter devices` does not show the emulator

Run in this order:

```bash
adb devices -l
flutter devices
flutter doctor -v
```

Confirm the emulator is fully booted:

```bash
adb -s emulator-5554 shell getprop sys.boot_completed
```

Expected:

```text
1
```

If the value is empty, wait and check again. A device can appear as `device` before Android has finished booting.

If `flutter doctor` reports an Android SDK error, see 7.7.

### 7.7 `aapt` / Android toolchain errors

Symptom:

```text
Android SDK file not found: .../build-tools/36.0.0/aapt
```

Cause: `ANDROID_HOME` is pointing at `D:\emulator\android-sdk`, which contains `aapt.exe`, not the Linux `aapt`.

Check:

```bash
echo "$ANDROID_HOME"
ls -l "$ANDROID_HOME/build-tools/36.0.0/aapt"
ls -l "$ANDROID_HOME/platforms/android-36/android.jar"
```

Fix:

```bash
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0"
flutter doctor --android-licenses
flutter doctor -v
```

Do not add `D:\emulator\android-sdk\platform-tools` to the Linux `PATH` ahead of `$ANDROID_HOME/platform-tools`.

### 7.8 Multiple `adb` binaries found

Typical warning:

```text
! Multiple adb binaries found:
  - /home/grepmind/Android/Sdk/platform-tools/adb
  - /usr/lib/android-sdk/platform-tools/adb
```

This is usually harmless because the SDK path comes first. Confirm:

```bash
command -v adb
adb version
```

Expected:

```text
/home/grepmind/Android/Sdk/platform-tools/adb
```

Optional cleanup of the old Ubuntu package:

```bash
sudo apt remove adb
```

Do not remove the SDK copy under `/home/grepmind/Android/Sdk/platform-tools`.

### 7.9 ADB version mismatch

Check both versions:

```bash
adb version
/mnt/d/emulator/android-sdk/platform-tools/adb.exe version
```

Both must match. The verified pair is `37.0.1-15733141`.

Update the Linux side:

```bash
sdkmanager "platform-tools"
```

Update the Windows side through Android Studio's SDK Manager, then restart the server:

```powershell
D:\emulator\android-sdk\platform-tools\adb.exe kill-server
D:\emulator\android-sdk\platform-tools\adb.exe -a start-server
```

### 7.10 Emulator is `offline` or `unauthorized`

Try:

```bash
adb reconnect offline
adb devices -l
```

If that does not help, restart the Windows ADB server and the emulator. For an emulator that is stuck, perform a cold boot from Android Studio, or launch with:

```powershell
& "D:\emulator\android-sdk\emulator\emulator.exe" -avd Medium_Phone_API_37.0 -no-snapshot-load
```

If authorization is the issue, open the emulator, confirm the RSA fingerprint prompt, and retry.

### 7.11 Windows firewall

The Windows firewall rule for the bridge is:

```powershell
New-NetFirewallRule -DisplayName "WSL ADB Bridge" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5037
```

Check it:

```powershell
Get-NetFirewallRule -DisplayName "WSL ADB Bridge" | Format-List Name,Enabled,Direction,Action
```

Only investigate the firewall after confirming that Windows is listening on `0.0.0.0:5037`. A listener on `127.0.0.1` is an ADB binding problem, not a firewall problem.

### 7.12 Port 5037 is in a Windows excluded range

Hyper-V and WSL can reserve TCP port ranges. Check:

```powershell
netsh interface ipv4 show excludedportrange protocol=tcp
```

If 5037 falls inside an excluded range, Windows cannot bind the ADB server there. Free the port by changing Windows' dynamic port range or restarting the relevant Windows services, or use a different ADB port consistently on both sides.

The verified environment does not have 5037 in an excluded range.

### 7.13 Emulator will not start

Check the AVD exists:

```powershell
D:\emulator\android-sdk\emulator\emulator.exe -list-avds
```

Expected:

```text
Medium_Phone_API_37.0
```

Check for stale emulator processes:

```powershell
tasklist /FI "IMAGENAME eq emulator.exe"
```

If stale processes exist:

```powershell
taskkill /F /IM emulator.exe /T
```

Then start the emulator again. If the AVD is missing, recreate it in Android Studio Device Manager.

### 7.14 Full recovery sequence

Use this when the normal checks are inconclusive.

1. Close the Flutter app.
2. Close the emulator.
3. On Windows, stop ADB:

```powershell
D:\emulator\android-sdk\platform-tools\adb.exe kill-server
```

4. Start one broadcast ADB server:

```powershell
D:\emulator\android-sdk\platform-tools\adb.exe -a start-server
```

5. Confirm the listener:

```powershell
netstat -ano | findstr :5037
```

It must show `0.0.0.0:5037`.

6. Start the emulator from Android Studio or:

```powershell
& "D:\emulator\android-sdk\emulator\emulator.exe" -avd Medium_Phone_API_37.0
```

7. Open a new WSL terminal and verify:

```bash
echo "$ADB_SERVER_SOCKET"
adb devices -l
flutter doctor -v
flutter devices
```

8. Clean and rerun the app:

```bash
flutter clean
flutter pub get
flutter run -d emulator-5554
```

## 8. Diagnostic command cheat sheet

### Windows PowerShell

```powershell
# ADB server and listener
netstat -ano | findstr :5037
tasklist /FI "IMAGENAME eq adb.exe"

# Restart on all interfaces
cd D:\emulator\android-sdk\platform-tools
.\adb.exe kill-server
.\adb.exe -a start-server

# Devices from Windows
.\adb.exe devices -l

# AVDs
D:\emulator\android-sdk\emulator\emulator.exe -list-avds

# Firewall rule
Get-NetFirewallRule -DisplayName "WSL ADB Bridge"

# Excluded port ranges
netsh interface ipv4 show excludedportrange protocol=tcp
```

### WSL

```bash
# Current host and bridge
ip route show default
echo "$ADB_SERVER_SOCKET"

# No local ADB server should be listening on 5037
ss -ltnp | grep ':5037'

# SDK and binaries
echo "$ANDROID_HOME"
command -v adb
adb version
ls -l "$ANDROID_HOME/build-tools/36.0.0/aapt"

# Devices
adb devices -l
adb -s emulator-5554 shell getprop sys.boot_completed

# Flutter
flutter doctor -v
flutter devices
```

### WSL view of the Windows listener

```bash
/mnt/c/Windows/System32/netstat.exe -ano | grep ':5037'
```

## 9. Notes and guardrails

- This setup is local-only. Do not expose the ADB bridge to the public internet.
- This guide assumes WSL2 NAT networking, which is the current mode (`wslinfo --networking-mode`). Revalidate the bridge if WSL is switched to mirrored networking.
- The Windows ADB server must listen on `0.0.0.0:5037`; WSL connections to Windows `127.0.0.1` do not work in NAT mode.
- `10.255.255.254` is never the Windows host address in this setup.
- Keep both ADB copies on the same version. A client/server mismatch can cause device detection failures.
- Use the Windows emulator for the GUI and the Linux SDK for builds. Mixing Windows build tools into the Linux SDK causes `aapt` and path errors.
- `flutter emulators` inside WSL cannot launch Windows AVDs. Start the emulator from Windows or with the WSL `emulator.exe` command above.
- If Windows reboots, start ADB with `-a start-server` once before relying on WSL device detection.
- Backups of the shell configuration are stored as `~/.bashrc.bak-adb-fix` and `~/.profile.bak-adb-fix`.
