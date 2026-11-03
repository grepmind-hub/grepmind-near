# Mobile emulator runner

Run these commands from PowerShell at the repository root:

```powershell
./scripts/mobile_emulator.ps1 -Action Status
./scripts/mobile_emulator.ps1 -Action Start
./scripts/mobile_emulator.ps1 -Action Stop
./scripts/mobile_emulator.ps1 -Action Restart
./scripts/mobile_emulator.ps1 -Action Build
./scripts/mobile_emulator.ps1 -Action Run
./scripts/mobile_emulator.ps1 -Action BuildRun
```

- `Start` launches the configured Windows AVD and waits until Android reports boot complete.
- `Stop` shuts down the selected emulator through its ADB console. It leaves the ADB server running.
- `Restart` performs a clean emulator shutdown and starts it again.
- `Build` builds a debug APK with the WSL Flutter SDK.
- `Run` starts the AVD if needed, verifies that WSL can reach the emulator through Windows ADB, then attaches `flutter run` in WSL. Press `q` in that terminal to end the Flutter session.
- `BuildRun` starts the AVD if needed, builds the APK, installs it, and opens the Android activity.
- `Status` reports ADB/emulator availability and the configured paths without changing emulator state.

The default values target this workstation's Pixel 8 AVD, Windows Android SDK, WSL Flutter/Android SDK, and local API URL. Override them when needed:

```powershell
./scripts/mobile_emulator.ps1 -Action Run -AvdName Pixel_8 -DeviceId emulator-5554 -ApiBaseUrl http://172.18.160.150:80
```

The Windows ADB server is started with `-a` so WSL can connect through its default NAT gateway. If Windows Firewall blocks that connection, allow the local ADB server on the private WSL network; the script does not change firewall rules. `Stop` targets only the selected AVD/device and does not stop WSL or the shared ADB server.

If Windows has reserved or occupied ADB port 5037, use an alternate local ADB server port:

```powershell
./scripts/mobile_emulator.ps1 -Action BuildRun -AdbServerPort 5039
```

The runner passes the selected port to Windows ADB and WSL Flutter. On a non-default server port, the emulator may not auto-register with ADB; the runner now connects the Pixel AVD through its local `localhost:5555` transport and uses that serial for install/run. Android may display an **Allow USB debugging** prompt when using a new ADB server key; approve that prompt on the emulator manually.

If ADB reports `failed to create fdevent interrupt socketpair: Invalid argument` when started from a restricted process, rerun the PowerShell runner in a normal authorized Windows session. This is a local ADB process startup failure and occurs before the emulator transport is contacted.
