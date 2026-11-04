#!/usr/bin/env python3
"""Inject or remove reversible catalog samples for the local Home feed preview.

This tool only operates on the generated QA preview businesses listed in
backend/home-preview-injection.json. It authenticates through local OTP and
creates/deletes entries through the merchant API, never direct SQL writes.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PREVIEW_MANIFEST = ROOT / "backend" / "home-preview-injection.json"
ITEM_MANIFEST = ROOT / "backend" / "new-near-you-injection.json"
API = "http://127.0.0.1:8080/api/v1"
PRODUCTS = [
    ("Premium Sona Masoori Rice — 5 kg", 420, "Polished medium-grain rice for everyday meals. Sample preview listing."),
    ("Cold-Pressed Mustard Oil — 1 L", 185, "Traditional cold-pressed mustard oil. Sample preview listing."),
    ("Organic Toor Dal — 1 kg", 165, "Cleaned and packed toor dal for home cooking. Sample preview listing."),
    ("Farm Fresh Cow Ghee — 500 ml", 345, "A 500 ml pack of aromatic cow ghee. Sample preview listing."),
    ("Whole Cashew Nuts — 250 g", 220, "Select whole cashew nuts in a 250 g pack. Sample preview listing."),
]
SERVICES = [
    ("Tap and Pipe Leak Repair", 350, 1500, "Inspection and repair for leaking taps and household water pipes. Sample preview listing."),
    ("Bathroom Fixture Installation", 700, 3500, "Installation of taps, showers and standard bathroom fixtures. Sample preview listing."),
    ("Drain Blockage Clearing", 500, 1800, "Clearing of common kitchen and bathroom drain blockages. Sample preview listing."),
    ("Overhead Water Tank Cleaning", 900, 2200, "Cleaning service for accessible residential overhead water tanks. Sample preview listing."),
    ("Emergency Plumbing Visit", 400, 1200, "Local visit for urgent household plumbing inspection. Sample preview listing."),
]


class PreviewError(RuntimeError):
    pass


def request(method: str, path: str, payload=None, token: str | None = None):
    body = None if payload is None else json.dumps(payload).encode()
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(API + path, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=20) as res:
            raw = res.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        # Do not print request bodies, OTPs, phone numbers, or bearer tokens.
        detail = exc.read().decode(errors="replace")
        raise PreviewError(f"{method} {path} returned HTTP {exc.code}: {detail[:300]}") from None
    except urllib.error.URLError as exc:
        raise PreviewError(f"Local API is unreachable: {exc.reason}") from None


def read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise PreviewError(f"Required fixture manifest is missing: {path.name}") from None


def owner_phones(cases):
    business_ids = sorted({case["BusinessID"] for case in cases})
    if any(not re.fullmatch(r"[0-9a-fA-F-]{36}", value) for value in business_ids):
        raise PreviewError("Fixture manifest contains an invalid business identifier")
    sql = "SELECT b.id::text || '|' || u.phone_e164 FROM businesses b JOIN users u ON u.id=b.owner_user_id WHERE b.id IN (" + ",".join(f"'{value}'" for value in business_ids) + ")"
    result = subprocess.run(
        ["docker", "exec", "grepmind_postgres", "psql", "-U", "grepmind", "-d", "grepmind_near", "-Atc", sql],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise PreviewError("Could not resolve QA fixture owners from the local development database")
    mapping = {}
    for line in result.stdout.splitlines():
        if "|" in line:
            business_id, phone = line.split("|", 1)
            mapping[business_id] = phone
    if any(value not in mapping for value in business_ids):
        raise PreviewError("A QA preview merchant no longer exists; do not target a retained merchant")
    users = {item["Phone"] for item in read_json(PREVIEW_MANIFEST).get("Users", [])}
    if any(phone not in users for phone in mapping.values()):
        raise PreviewError("A listed business is not owned by a user recorded in the QA fixture manifest")
    return mapping


def login(phone: str, cache: dict[str, str]):
    if phone in cache:
        return cache[phone]
    otp = request("POST", "/auth/otp/request", {"phone_e164": phone})["data"]
    code = otp.get("otp_code")
    if not code:
        raise PreviewError("Local OTP disclosure is disabled; fixture injection requires APP_ENV=local")
    session = request("POST", "/auth/otp/verify", {"phone_e164": phone, "otp_code": code})["data"]
    cache[phone] = session["access_token"]
    return cache[phone]


def fixture_targets(cases):
    targets = {}
    for city in ("Cuttack", "Jajpur"):
        grocery = next((item for item in cases if item["City"] == city and item["CategorySlug"] == "grocery"), None)
        plumber = next((item for item in cases if item["City"] == city and item["CategorySlug"] == "plumber"), None)
        if not grocery or not plumber or not grocery.get("BusinessName", "").startswith("QA PREVIEW") or not plumber.get("BusinessName", "").startswith("QA PREVIEW"):
            raise PreviewError(f"Expected generated QA grocery and plumber businesses in {city}")
        targets[city] = {"products": grocery, "services": plumber}
    return targets


def inject():
    preview = read_json(PREVIEW_MANIFEST)
    if ITEM_MANIFEST.exists():
        raise PreviewError("An item injection manifest already exists; verify it or run cleanup first")
    cases = preview.get("Cases", [])
    targets = fixture_targets(cases)
    phones = owner_phones(cases)
    tokens: dict[str, str] = {}
    ledger = {"Run": preview["Run"], "Records": []}
    ITEM_MANIFEST.write_text(json.dumps(ledger, indent=2), encoding="utf-8")
    try:
        for city, kinds in targets.items():
            for kind, entries in (("products", PRODUCTS), ("services", SERVICES)):
                fixture = kinds[kind]
                business_id = fixture["BusinessID"]
                token = login(phones[business_id], tokens)
                for index, entry in enumerate(entries, start=1):
                    if kind == "products":
                        name, price, description = entry
                        payload = {
                            "name": f"Sample · {name}",
                            "description": description,
                            "price": price,
                            "stock_status": "in_stock",
                            "is_published": True,
                            "image_url": fixture.get("ImageURL") or None,
                        }
                    else:
                        name, price_min, price_max, description = entry
                        payload = {
                            "name": f"Sample · {name}",
                            "description": description,
                            "indicative_price_min": price_min,
                            "indicative_price_max": price_max,
                            "is_active": True,
                        }
                    created = request("POST", f"/merchant/{kind}?business_id={business_id}", payload, token)["data"]
                    ledger["Records"].append({"id": created["id"], "type": kind, "city": city, "business_id": business_id, "name": payload["name"]})
                    ITEM_MANIFEST.write_text(json.dumps(ledger, indent=2), encoding="utf-8")
            print(f"Injected five sample products and five sample services for {city}.")
        verify(ledger, preview, tokens)
        print("PASS customer feed: all injected product and service entries are visible in their city feeds.")
        print(f"Injection IDs are recorded in {ITEM_MANIFEST.relative_to(ROOT)} for exact cleanup.")
    except Exception:
        # Keep the partial ledger so cleanup can safely remove only created IDs.
        raise


def verify(ledger, preview, tokens):
    # New arrivals is intentionally public discovery data; exercising this
    # unauthenticated endpoint mirrors the customer Home feed without creating
    # another QA account just for verification.
    for city in ("Cuttack", "Jajpur"):
        for kind, api_kind in (("products", "products"), ("services", "services")):
            feed = request("GET", f"/catalog/new-arrivals?{urllib.parse.urlencode({'city': city, 'type': api_kind, 'limit': 50})}")["data"]
            actual = {item["id"] for item in feed}
            expected = {record["id"] for record in ledger["Records"] if record["city"] == city and record["type"] == kind}
            if len(expected) != 5 or not expected.issubset(actual):
                raise PreviewError(f"Customer feed verification failed for {city} {kind}; expected five newly published entries")


def cleanup():
    ledger = read_json(ITEM_MANIFEST)
    preview = read_json(PREVIEW_MANIFEST)
    cases = preview.get("Cases", [])
    phones = owner_phones(cases)
    tokens: dict[str, str] = {}
    deleted = 0
    for record in ledger.get("Records", []):
        business_id = record["business_id"]
        token = login(phones[business_id], tokens)
        request("DELETE", f"/merchant/{record['type']}/{record['id']}?business_id={business_id}", token=token)
        deleted += 1
    ITEM_MANIFEST.unlink(missing_ok=True)
    print(f"PASS cleanup: removed {deleted} catalog entries created by this script.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("inject", "verify", "cleanup"))
    args = parser.parse_args()
    try:
        if args.action == "inject":
            inject()
        elif args.action == "verify":
            ledger = read_json(ITEM_MANIFEST)
            verify(ledger, read_json(PREVIEW_MANIFEST), {})
            print("PASS customer Home feed: five sample products and five sample services are visible in each city.")
        else:
            cleanup()
    except (PreviewError, KeyError, subprocess.SubprocessError) as exc:
        print(f"FAILED: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
