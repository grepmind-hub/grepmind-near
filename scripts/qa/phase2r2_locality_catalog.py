#!/usr/bin/env python3
"""Create, track, and remove local Phase 2R.2 catalog QA fixtures.

Run inside WSL with GREPMIND_QA_ADMIN_PHONE set to an authorized local admin:
  python3 scripts/qa/phase2r2_locality_catalog.py create
  python3 scripts/qa/phase2r2_locality_catalog.py cleanup

The script refuses non-loopback API hosts and requires the local-only OTP echo.
It never creates customer orders. Product fixtures are explicitly marked QA.
"""
from __future__ import annotations

import json
import os
import struct
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import zlib
from pathlib import Path

API = os.environ.get("GREPMIND_QA_API", "http://localhost:8080/api/v1")
PHONE = os.environ.get("GREPMIND_QA_ADMIN_PHONE", "")
MANIFEST = Path(tempfile.gettempdir()) / "grepmind-near-phase2r2-qa.json"
DISTRICTS = {
    "Cuttack": "02200000-0000-4000-8000-000000000001",
    "Jajpur": "02200000-0000-4000-8000-000000000002",
}
LOCALITIES = {
    ("Cuttack", "Kuanpal"): "02200000-0000-4000-8000-000000000101",
    ("Jajpur", "Chhatia"): "02200000-0000-4000-8000-000000000201",
}
FIXTURES = [
    {"district": "Cuttack", "locality": "Kuanpal", "vertical": "food", "name": "QA Chicken Biryani", "sku": "QA-P2R2-FOOD-CUTTACK-KUANPAL", "variant_sku": "QA-P2R2-V-FOOD-CK", "variant": "QA portion", "unit": "1 serving", "price": 9900, "color": (225, 125, 55)},
    {"district": "Cuttack", "locality": "Kuanpal", "vertical": "grocery", "name": "QA Rice 1 kg", "sku": "QA-P2R2-GROCERY-CUTTACK-KUANPAL", "variant_sku": "QA-P2R2-V-GROCERY-CK", "variant": "QA pack", "unit": "1 kg", "price": 6900, "color": (74, 147, 105)},
    {"district": "Jajpur", "locality": "Chhatia", "vertical": "food", "name": "QA Veg Thali", "sku": "QA-P2R2-FOOD-JAJPUR-CHHATIA", "variant_sku": "QA-P2R2-V-FOOD-JC", "variant": "QA thali", "unit": "1 plate", "price": 12900, "color": (210, 150, 56)},
    {"district": "Jajpur", "locality": "Chhatia", "vertical": "grocery", "name": "QA Milk 1 L", "sku": "QA-P2R2-GROCERY-JAJPUR-CHHATIA", "variant_sku": "QA-P2R2-V-GROCERY-JC", "variant": "QA bottle", "unit": "1 L", "price": 6800, "color": (83, 132, 189)},
]


def request(path: str, method: str = "GET", token: str = "", body=None, data=None, content_type="application/json"):
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    payload = None
    if body is not None:
        payload = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    elif data is not None:
        payload = data
        headers["Content-Type"] = content_type
    req = urllib.request.Request(API + path, data=payload, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=25) as response:
            raw = response.read()
            return response.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")
        raise RuntimeError(f"{method} {path} returned HTTP {exc.code}: {detail[:400]}") from exc


def auth_token() -> str:
    if not PHONE:
        raise RuntimeError("Set GREPMIND_QA_ADMIN_PHONE to an existing local Admin account.")
    _, challenge = request("/auth/otp/request", "POST", body={"phone_e164": PHONE})
    otp = challenge.get("data", {}).get("otp_code")
    if not otp:
        raise RuntimeError("The API did not return a local development OTP; refusing to use an external SMS flow.")
    _, verified = request("/auth/otp/verify", "POST", body={"phone_e164": PHONE, "otp_code": otp})
    result = verified.get("data", {})
    roles = result.get("user", {}).get("roles", [])
    if "admin" not in roles:
        raise RuntimeError("The configured local account is not an Admin; no catalog data was created.")
    return result["access_token"]


def png(color: tuple[int, int, int]) -> bytes:
    """Create a small unmistakable QA artwork using only Python stdlib."""
    width, height = 480, 320
    pixels = bytearray()
    for y in range(height):
        row = bytearray([0])
        for x in range(width):
            # Soft vertical gradient plus a warm central plate/basket motif.
            mix = y / max(1, height - 1)
            base = tuple(int(c * (1 - mix * .35) + 248 * mix * .35) for c in color)
            dx, dy = x - width // 2, y - height // 2
            r2 = dx * dx + dy * dy
            if r2 < 86 * 86:
                base = (255, 250, 238)
            if r2 < 69 * 69:
                base = tuple(max(0, min(255, c + 8)) for c in color)
            # Small colorful garnish/product marks.
            if ((x - 205) ** 2 + (y - 145) ** 2 < 12 ** 2) or ((x - 269) ** 2 + (y - 177) ** 2 < 10 ** 2):
                base = (244, 198, 67)
            row.extend(base)
        pixels.extend(row)
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">2I5B", width, height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(bytes(pixels), 8)) + chunk(b"IEND", b"")


def upload_image(token: str, item: dict) -> dict:
    boundary = "----GrepmindLocalQA"
    content = png(item["color"])
    body = (
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"purpose\"\r\n\r\nqa-phase2r2\r\n"
        f"--{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{item['sku']}.png\"\r\nContent-Type: image/png\r\n\r\n"
    ).encode() + content + f"\r\n--{boundary}--\r\n".encode()
    _, result = request("/media/upload", "POST", token, data=body, content_type=f"multipart/form-data; boundary={boundary}")
    return result["data"]


def locations() -> dict:
    _, result = request("/catalog/locations")
    by_name = {item["name"]: item for item in result.get("data", [])}
    return by_name


def create() -> None:
    if MANIFEST.exists():
        raise RuntimeError(f"QA manifest already exists at {MANIFEST}; clean it up before creating more fixtures.")
    token = auth_token()
    by_district = locations()
    created = []
    manifest = {"products": [], "media": []}
    try:
        for item in FIXTURES:
            district = by_district.get(item["district"])
            if not district or district["id"] != DISTRICTS[item["district"]]:
                raise RuntimeError(f"Configured district ID mismatch for {item['district']}.")
            locality = next((loc for loc in district["localities"] if loc["name"] == item["locality"]), None)
            if not locality or locality["id"] != LOCALITIES[(item["district"], item["locality"]) ] or not locality["delivery_enabled"]:
                raise RuntimeError(f"Configured enabled locality mismatch for {item['district']} / {item['locality']}.")
            _, cats = request(f"/admin/catalog/categories?vertical={item['vertical']}", token=token)
            category = next((c for c in cats.get("data", []) if c.get("slug") == item["vertical"] and c.get("is_active")), None)
            if not category:
                raise RuntimeError(f"Active {item['vertical']} root category not found.")
            media = upload_image(token, item)
            manifest["media"].append({"object_key": media["object_key"], "upload_id": media["id"]})
            payload = {
                "sku": item["sku"], "category_id": category["id"], "name": item["name"],
                "description": "TEMPORARY QA FIXTURE — test image and test price; not a real product or offer.",
                "image_urls": [media["url"]], "status": "active", "areas": [{
                    "district_id": district["id"], "locality_id": locality["id"]
                }],
                "variants": [{"sku": item["variant_sku"], "name": item["variant"], "unit_label": item["unit"], "price_minor": item["price"], "currency": "INR"}],
            }
            _, created_response = request("/admin/catalog/products", "POST", token, body=payload)
            product_id = created_response["data"]["id"]
            created.append(product_id)
            manifest["products"].append({"id": product_id, "sku": item["sku"], "name": item["name"], "district": item["district"], "locality": item["locality"], "vertical": item["vertical"], "price_minor": item["price"], "image_url": media["url"]})
            print(f"Created {item['name']} ({product_id})")
        MANIFEST.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        print(f"QA manifest: {MANIFEST}")
    except Exception:
        for product_id in created:
            try: request(f"/admin/catalog/products/{product_id}", "DELETE", token)
            except Exception: pass
        raise


def validate() -> None:
    if not MANIFEST.exists():
        raise RuntimeError("No QA manifest found; run create first.")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    expected = {(p["district"], p["locality"], p["vertical"]): p for p in manifest["products"]}
    passed = 0
    for (district, locality, vertical), fixture in expected.items():
        locality_id = LOCALITIES[(district, locality)]
        params = urllib.parse.urlencode({"vertical": vertical, "city": district, "locality_id": locality_id})
        _, response = request("/catalog/products?" + params)
        items = response.get("data", [])
        if len(items) != 1 or items[0]["name"] != fixture["name"]:
            raise RuntimeError(f"Expected exactly {fixture['name']} in {district}/{locality} {vertical}; got {[p.get('name') for p in items]}.")
        product = items[0]
        if not product.get("image_urls") or not product.get("variants") or product["variants"][0].get("price_minor") != fixture["price_minor"]:
            raise RuntimeError(f"Image or test price validation failed for {fixture['name']}.")
        image_url = product["image_urls"][0]
        if not image_url.startswith("/media/"):
            raise RuntimeError(f"QA image is not a local media asset for {fixture['name']}.")
        with urllib.request.urlopen("http://localhost" + image_url, timeout=20) as image_response:
            if image_response.status != 200 or not image_response.headers.get("Content-Type", "").startswith("image/png"):
                raise RuntimeError(f"QA image did not load as PNG for {fixture['name']}.")
        forbidden = {"supply_price_minor", "partner_cost", "business_id", "mapping_id"}
        if forbidden.intersection(product):
            raise RuntimeError(f"Internal partner field leaked for {fixture['name']}.")
        detail_query = urllib.parse.urlencode({"vertical": vertical, "city": district, "locality_id": locality_id})
        _, detail = request(f"/catalog/products/{fixture['id']}?{detail_query}")
        if detail.get("data", {}).get("id") != fixture["id"]:
            raise RuntimeError(f"Exact product detail failed for {fixture['name']}.")
        search_query = urllib.parse.urlencode({"vertical": vertical, "city": district, "locality_id": locality_id, "q": fixture["name"]})
        _, search = request("/catalog/products?" + search_query)
        if [p.get("id") for p in search.get("data", [])] != [fixture["id"]]:
            raise RuntimeError(f"Search did not return the expected product {fixture['name']}.")
        print(f"PASS {district}/{locality} {vertical}: {fixture['name']}, price, image reference, detail, search")
        passed += 1
    # District-wide catalog visibility is independent from locality delivery.
    for district, vertical in (("Cuttack", "food"), ("Cuttack", "grocery"), ("Jajpur", "food"), ("Jajpur", "grocery")):
        params = urllib.parse.urlencode({"vertical": vertical, "city": district})
        _, result = request("/catalog/products?" + params)
        if len(result.get("data", [])) != 1:
            raise RuntimeError(f"District-level visibility failed for {district}/{vertical}.")
        passed += 1
    mismatch = urllib.parse.urlencode({"vertical": "food", "city": "Cuttack", "locality_id": LOCALITIES[("Jajpur", "Chhatia")]})
    try:
        request("/catalog/products?" + mismatch)
        raise RuntimeError("Cross-district locality ID was not rejected.")
    except RuntimeError as error:
        if "HTTP 400" not in str(error): raise
    planned = urllib.parse.urlencode({"vertical": "food", "city": "Cuttack", "locality_id": "02200000-0000-4000-8000-000000000102"})
    _, result = request("/catalog/products?" + planned)
    if result.get("data") != [] or result.get("meta", {}).get("delivery_available") is not False:
        raise RuntimeError("Planned Jagatpur locality was incorrectly presented as deliverable.")
    print(f"PASS {passed + 2} checks: locality scoping, district visibility, product details, search, partner-cost omission, planned-area status")


def cleanup() -> None:
    if not MANIFEST.exists():
        raise RuntimeError("No QA manifest found; nothing was removed.")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    token = auth_token()
    for item in manifest["products"]:
        request(f"/admin/catalog/products/{item['id']}", "DELETE", token)
    ids = [item["id"] for item in manifest["products"]]
    keys = [item["object_key"] for item in manifest["media"]]
    if any(not key.startswith("qa-phase2r2/") or ".." in key.split("/") for key in keys):
        raise RuntimeError("Refusing cleanup: unexpected QA media object key.")
    # Remove only records created by this run. Product deletion by Admin API is
    # recorded first; exact IDs are then hard-deleted to leave no QA catalog rows.
    id_sql = ",".join("'" + value.replace("'", "") + "'::uuid" for value in ids)
    key_sql = ",".join("'" + value.replace("'", "") + "'" for value in keys)
    sql = f"DELETE FROM platform_catalog_products WHERE id IN ({id_sql}); DELETE FROM media_uploads WHERE object_key IN ({key_sql}) AND purpose='qa-phase2r2';"
    subprocess.run(["docker", "exec", "grepmind_postgres", "psql", "-v", "ON_ERROR_STOP=1", "-U", "grepmind", "-d", "grepmind_near", "-c", sql], check=True, capture_output=True, text=True)
    if keys:
        # Credentials stay inside the MinIO container environment and are not
        # printed or passed through the host process environment.
        for key in keys:
            subprocess.run(["docker", "exec", "grepmind_minio", "sh", "-lc", f'mc alias set qa-local http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null && mc rm --force "qa-local/${{S3_BUCKET:-grepmind-near}}/{key}" >/dev/null'], check=True, capture_output=True, text=True)
    MANIFEST.unlink()
    print(f"Removed {len(ids)} QA products and {len(keys)} QA images; manifest deleted.")


def main() -> None:
    parsed = urllib.parse.urlparse(API)
    if parsed.scheme != "http" or parsed.hostname not in {"localhost", "127.0.0.1"}:
        raise RuntimeError("This QA fixture tool only runs against local HTTP API hosts.")
    action = sys.argv[1] if len(sys.argv) > 1 else ""
    if action == "create": create()
    elif action == "cleanup": cleanup()
    elif action == "validate": validate()
    else: raise RuntimeError("Usage: phase2r2_locality_catalog.py create|validate|cleanup")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
