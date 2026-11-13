#!/usr/bin/env python3
"""Accept the exact Phase 3G-D QA offer on Rider B's local emulator."""

from __future__ import annotations

import subprocess
import sys
import time
import xml.etree.ElementTree as ET

ADB = "/mnt/d/emulator/android-sdk/platform-tools/adb.exe"
SERIAL = "emulator-5554"
TARGET_TEXT = "QA 3G-D Biryani"


def adb(*args: str) -> str:
    return subprocess.check_output([ADB, "-s", SERIAL, *args], text=True, timeout=8)


def dump_tree() -> ET.Element:
    adb("shell", "uiautomator", "dump", "/sdcard/window.xml")
    return ET.fromstring(adb("shell", "cat", "/sdcard/window.xml"))


def find_offer(root: ET.Element) -> ET.Element | None:
    for node in root.iter("node"):
        desc = node.attrib.get("content-desc", "")
        if TARGET_TEXT in desc:
            for child in node.iter("node"):
                if child.attrib.get("content-desc") == "Accept":
                    return child
    return None


def main() -> int:
    deadline = time.monotonic() + 50
    while time.monotonic() < deadline:
        try:
            root = dump_tree()
            button = find_offer(root)
            if button is not None:
                # The offer card is visible; use the device's accessible button bounds.
                bounds = button.attrib.get("bounds", "")
                values = bounds.replace("][", ",").strip("[]").split(",")
                if len(values) != 4:
                    raise RuntimeError(f"Unexpected Accept button bounds: {bounds}")
                x1, y1, x2, y2 = map(int, values)
                adb("shell", "input", "tap", str((x1 + x2) // 2), str((y1 + y2) // 2))
                time.sleep(2)
                root = dump_tree()
                # Verify the target no longer appears as an unaccepted incoming offer.
                incoming = next(
                    (n for n in root.iter("node") if n.attrib.get("content-desc", "").startswith("Incoming offers")),
                    None,
                )
                if incoming is not None and TARGET_TEXT in incoming.attrib.get("content-desc", ""):
                    raise RuntimeError("QA offer is still shown as incoming after the Accept tap")
                print("Rider B accepted the targeted QA offer through the emulator UI")
                return 0
        except (subprocess.SubprocessError, ET.ParseError, RuntimeError) as exc:
            print(f"Waiting for targeted offer: {exc}", file=sys.stderr)
        time.sleep(1)
    print("Timed out waiting for the targeted QA offer on Rider B", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
