"""Build independently licensed Australian nutrition snapshots for review."""
import argparse
from datetime import date
import json
import math
from pathlib import Path
import re
import sqlite3
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen
from time import sleep

RETAILERS = ("ALDI", "Woolworths", "Coles", "IGA")
OFF_URL = "https://world.openfoodfacts.org"
OFF_LICENCE = "ODbL-1.0"
PAGE_SIZE = 100
FIELDS = "code,product_name,product_name_en,brands,nutriments,stores_tags,countries_tags"
USER_AGENT = "SteadyStrength/0.1 (https://github.com/rikiwessels6-collab/steady-strength)"
MAX_BYTES = 10 * 1024 * 1024
NUTRIENTS = {"kcal": 950, "protein": 100, "carbs": 100, "fat": 100,
             "fibre": 100, "sugar": 100, "satFat": 100, "sodium": 40_000}


def https_url(value):
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password:
        raise ValueError("Expected an HTTPS source URL without credentials")
    return value


def download(url):
    request = Request(https_url(url), headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urlopen(request, timeout=45) as response:
        https_url(response.url)
        payload = response.read(MAX_BYTES + 1)
    if len(payload) > MAX_BYTES:
        raise ValueError("Feed exceeds the JSON download limit")
    return json.loads(payload)


def number(value, cap):
    if value is None or isinstance(value, bool):
        return None
    try:
        result = float(str(value).replace(",", "."))
    except ValueError:
        return None
    return result if math.isfinite(result) and 0 <= result <= cap else None


def open_food_facts(product, retailer, checked):
    code = product.get("code", "")
    if not isinstance(code, str) or not re.fullmatch(r"[0-9]{8,14}", code):
        return None
    if retailer.lower() not in (product.get("stores_tags") or []):
        return None
    if "en:australia" not in (product.get("countries_tags") or []):
        return None
    name = (product.get("product_name_en") or product.get("product_name") or "").strip()
    n = product.get("nutriments") or {}
    energy = number(n.get("energy-kcal_100g"), 950)
    if energy is None:
        kj = number(n.get("energy-kj_100g", n.get("energy_100g")), 3974.8)
        energy = None if kj is None else kj / 4.184
    per100 = {"kcal": energy, "protein": number(n.get("proteins_100g"), 100),
              "carbs": number(n.get("carbohydrates_100g"), 100), "fat": number(n.get("fat_100g"), 100),
              "fibre": number(n.get("fiber_100g"), 100), "sugar": number(n.get("sugars_100g"), 100),
              "satFat": number(n.get("saturated-fat_100g"), 100)}
    sodium = number(n.get("sodium_100g"), 40)
    salt = number(n.get("salt_100g"), 100)
    per100["sodium"] = sodium * 1000 if sodium is not None else (salt * 400 if salt is not None else None)
    if not name or any(per100[key] is None for key in ("kcal", "protein", "carbs", "fat")):
        return None
    return {"country": "AU", "category": "supermarket", "retailer": retailer,
            "licence": OFF_LICENCE, "sourceURL": f"{OFF_URL}/product/{code}", "checkedOn": checked,
            "item": {"id": code, "barcode": code, "name": name, "brand": product.get("brands"),
                     "per100": per100}}


def collect_retail(pages, checked, get=download, pause=sleep):
    records = {}
    for retailer in RETAILERS:
        for page in range(1, pages + 1):
            query = urlencode({"countries_tags": "en:australia", "stores_tags": retailer.lower(),
                               "fields": FIELDS, "page": page, "page_size": PAGE_SIZE,
                               "sort_by": "last_modified_t"})
            payload = get(f"{OFF_URL}/api/v2/search?{query}")
            products = payload["products"]
            if not isinstance(products, list):
                raise ValueError(f"Invalid product list for {retailer}")
            for product in products:
                record = open_food_facts(product, retailer, checked)
                if record:
                    # A multi-retailer product has a row per retailer.
                    records[(retailer, record["item"]["id"].zfill(14))] = record
            pause(7)  # OFF search limit: at most 10 requests/minute.
            if len(products) < PAGE_SIZE:
                break
        if not any(key[0] == retailer for key in records):
            print(f"No usable Open Food Facts rows returned for {retailer}")
    if not records:
        raise ValueError("Open Food Facts returned no usable Australian products")
    return list(records.values())


def validate_operator(record):
    if record["country"] != "AU" or record["category"] not in {"restaurant", "cafe", "coffee"}:
        raise ValueError("An operator row must describe an Australian restaurant, café or coffee product")
    https_url(record["sourceURL"])
    date.fromisoformat(record["checkedOn"])
    item = record["item"]
    if not re.fullmatch(r"(?:au-menu-|restaurant-serve-au-menu-)[a-z0-9][a-z0-9-]{0,99}", item["id"]):
        raise ValueError("Use a stable au-menu- or restaurant-serve-au-menu- identifier")
    for key in ("name", "brand"):
        if not isinstance(item.get(key), str) or not item[key].strip():
            raise ValueError(f"Missing food {key}")
    serving = item.get("servingGrams")
    by_serve = item["id"].startswith("restaurant-serve-")
    if by_serve and (serving != 100 or not item.get("servingLabel")):
        raise ValueError("A serve-based row needs a serving label and servingGrams of 100")
    if not by_serve and (type(serving) not in (float, int) or not 0 < serving <= 10_000):
        raise ValueError("Provide a physical serving amount for a per-100 row")
    if item.get("amountUnit") not in {None, "g", "mL"} or (by_serve and item.get("amountUnit") is not None):
        raise ValueError("Unexpected serving unit")
    for key, limit in NUTRIENTS.items():
        value = item["per100"].get(key)
        if value is None and key in {"fibre", "sugar", "satFat", "sodium"}:
            continue
        if type(value) not in (float, int) or number(value, limit * (10 if by_serve else 1)) is None:
            raise ValueError(f"{item['id']}: invalid or missing {key}")
    return record


def collect_operators(feeds, get=download):
    if not isinstance(feeds, list):
        raise ValueError("Expected a list of approved menu feeds")
    records = {}
    for feed in feeds:
        licence = feed["licence"]
        if not isinstance(licence, str) or not licence.strip():
            raise ValueError("An approved reuse licence or permission reference is required")
        snapshot = get(feed["url"])
        if snapshot["schemaVersion"] != 1 or not isinstance(snapshot["entries"], list):
            raise ValueError("Unsupported operator snapshot format")
        for row in snapshot["entries"]:
            record = validate_operator({**row, "licence": licence})
            key = record["item"]["id"]
            if key in records:
                raise ValueError(f"Duplicate menu product ID: {key}")
            records[key] = record
    return list(records.values())


def write_snapshot(output, name, records):
    ordered = sorted(records, key=lambda r: (r.get("retailer", ""), r["item"]["id"]))
    output.mkdir(parents=True, exist_ok=True)
    json_path = output / f"{name}.json"
    json_path.write_text(json.dumps({"schemaVersion": 1, "entries": ordered}, ensure_ascii=False,
                                    allow_nan=False, separators=(",", ":")) + "\n", encoding="utf-8")
    database = output / f"{name}.sqlite"
    database.unlink(missing_ok=True)
    with sqlite3.connect(database) as db:
        db.execute("""CREATE TABLE nutrition (
            country TEXT NOT NULL CHECK (country = 'AU'), category TEXT NOT NULL,
            retailer TEXT NOT NULL, item_id TEXT NOT NULL, barcode TEXT, name TEXT NOT NULL,
            source_url TEXT NOT NULL, licence TEXT NOT NULL, checked_on TEXT NOT NULL,
            payload TEXT NOT NULL, PRIMARY KEY (retailer, item_id))""")
        db.executemany("INSERT INTO nutrition VALUES (?,?,?,?,?,?,?,?,?,?)", [
            (r["country"], r["category"], r.get("retailer", ""), r["item"]["id"], r["item"].get("barcode"),
             r["item"]["name"], r["sourceURL"], r["licence"], r["checkedOn"], json.dumps(r["item"], allow_nan=False))
            for r in ordered
        ])
        db.execute("CREATE INDEX nutrition_barcode ON nutrition(barcode)")
        db.execute("CREATE INDEX nutrition_name ON nutrition(name COLLATE NOCASE)")
        if db.execute("PRAGMA quick_check").fetchone() != ("ok",):
            raise ValueError(f"Invalid SQLite output: {name}")
    print(f"{name}: {len(ordered)} validated rows")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--retail-pages", type=int, choices=range(1, 21), default=5)
    parser.add_argument("--feed-config", type=Path)
    args = parser.parse_args()
    feeds = json.loads(args.feed_config.read_text()) if args.feed_config else []
    retail = collect_retail(args.retail_pages, date.today().isoformat())
    operators = collect_operators(feeds)
    write_snapshot(args.output, "au-supermarkets-odbl", retail)
    write_snapshot(args.output, "au-operator-menus", operators)


if __name__ == "__main__":
    main()
