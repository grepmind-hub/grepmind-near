#!/bin/bash
original=("$@")
args=()
for arg in "${original[@]}"; do
  case "$arg" in
    /mnt/[a-zA-Z]/*) arg="$(wslpath -w "$arg")" ;;
  esac
  args+=("$arg")
done
exec /mnt/d/emulator/android-sdk/platform-tools/adb.exe "${args[@]}"
