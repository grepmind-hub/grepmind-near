#!/usr/bin/env bash
set -euo pipefail

FLUTTER_ROOT="${FLUTTER_ROOT:-$HOME/projects/flutter-setup/develop/flutter}"
ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
ANDROID_SDK_ROOT="$ANDROID_HOME"
ANDROID_DEVICE_ID="${ANDROID_DEVICE_ID:-emulator-5554}"
API_BASE_URL="${API_BASE_URL:-http://10.0.2.2:80}"

export ANDROID_HOME ANDROID_SDK_ROOT
export PATH="$FLUTTER_ROOT/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

if [[ -z "${ADB_SERVER_SOCKET:-}" ]]; then
  WSL_GATEWAY="$(ip route show default | awk '/^default/ {print $3; exit}')"
  if [[ -z "$WSL_GATEWAY" ]]; then
    echo "Could not determine the WSL network gateway for Windows ADB." >&2
    exit 1
  fi
  export ADB_SERVER_SOCKET="tcp:${WSL_GATEWAY}:5037"
fi

if [[ ! -x "$FLUTTER_ROOT/bin/flutter" ]]; then
  echo "Flutter SDK not found at $FLUTTER_ROOT/bin/flutter" >&2
  exit 1
fi
if [[ ! -x "$ANDROID_HOME/platform-tools/adb" ]]; then
  echo "Linux Android SDK ADB not found at $ANDROID_HOME/platform-tools/adb" >&2
  exit 1
fi

echo "Flutter: $FLUTTER_ROOT"
echo "Android SDK: $ANDROID_HOME"
echo "ADB server: $ADB_SERVER_SOCKET"
echo "API base URL: $API_BASE_URL"
adb version
adb devices -l

cd /mnt/d/grepmind-near/apps/mobile
"$FLUTTER_ROOT/bin/flutter" run \
  --dart-define="API_BASE_URL=$API_BASE_URL" \
  -d "$ANDROID_DEVICE_ID" 2>&1 | tee /tmp/phase4_build.log
