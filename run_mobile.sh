#!/usr/bin/env bash
export PATH="/home/grepmind/projects/flutter-setup/develop/flutter/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
export ADB_SERVER_SOCKET="tcp:$(ip route show default | awk '/^default/ {print $3; exit}'):5037"
echo "Connecting to Windows ADB server at: $ADB_SERVER_SOCKET"
adb devices
cd /mnt/d/grepmind-near/apps/mobile
flutter run --dart-define=API_BASE_URL=http://172.18.160.150:80 -d emulator-5554 2>&1 | tee /tmp/phase4_build.log
