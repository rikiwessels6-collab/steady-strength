import json
from pathlib import Path
import sqlite3
from tempfile import TemporaryDirectory
import unittest
from urllib.parse import parse_qs, urlparse

from collect import collect_operators, collect_retail, open_food_facts, write_snapshot


class CatalogueTests(unittest.TestCase):
    def setUp(self):
        self.product = {
            "code": "0123456789012", "product_name": "Example milk",
            "stores_tags": ["coles", "iga"], "countries_tags": ["en:australia"],
            "nutriments": {"energy-kj_100g": 418.4, "proteins_100g": "4,5",
                           "carbohydrates_100g": 13, "fat_100g": 3, "salt_100g": 0.1},
        }
        self.operator = {
            "country": "AU", "category": "cafe", "sourceURL": "https://example.com/menu",
            "checkedOn": "2026-11-19",
            "item": {"id": "restaurant-serve-au-menu-latte", "name": "Latte", "brand": "Example Café",
                     "servingGrams": 100, "servingLabel": "One cup",
                     "per100": {"kcal": 133, "protein": 7, "carbs": 13, "fat": 6}},
        }
        self.feed = {"url": "https://example.com/feed.json", "licence": "CC-BY-4.0"}

    def test_retail_membership_country_and_numeric_conversion(self):
        row = open_food_facts(self.product, "Coles", "2026-11-19")
        self.assertAlmostEqual(row["item"]["per100"]["kcal"], 100)
        self.assertEqual(row["item"]["per100"]["sodium"], 40)
        self.assertIsNone(row["item"]["per100"]["fibre"])
        self.assertIsNone(open_food_facts(self.product, "ALDI", "2026-11-19"))
        self.assertIsNone(open_food_facts({**self.product, "countries_tags": ["en:france"]}, "Coles", "2026-11-19"))
        self.assertIsNone(open_food_facts({**self.product, "nutriments": {"energy-kcal_100g": 42}}, "Coles", "2026-11-19"))

    def test_queries_four_retailers_and_deduplicates_within_each(self):
        queries = []

        def get(url):
            queries.append(parse_qs(urlparse(url).query))
            return {"products": [self.product, self.product]}

        rows = collect_retail(2, "2026-11-19", get=get, pause=lambda _: None)
        self.assertEqual([q["stores_tags"][0] for q in queries], ["aldi", "woolworths", "coles", "iga"])
        self.assertTrue(all(q["countries_tags"] == ["en:australia"] for q in queries))
        self.assertEqual([r["retailer"] for r in rows], ["Coles", "IGA"])

    def test_operator_validation_rejects_duplicate_and_bad_provenance(self):
        def fetch(*rows):
            return lambda _: {"schemaVersion": 1, "entries": list(rows)}


        self.assertEqual(collect_operators([self.feed], get=fetch(self.operator))[0]["licence"], "CC-BY-4.0")
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            collect_operators([self.feed], get=fetch(self.operator, self.operator))
        with self.assertRaisesRegex(ValueError, "Australian"):
            collect_operators([self.feed], get=fetch({**self.operator, "country": "NZ"}))
        with self.assertRaisesRegex(ValueError, "HTTPS"):
            collect_operators([self.feed], get=fetch({**self.operator, "sourceURL": "http://example.com"}))
        with self.assertRaisesRegex(ValueError, "licence"):
            collect_operators([{**self.feed, "licence": ""}], get=fetch(self.operator))

    def test_invalid_nutrient_and_missing_serving_size(self):
        item = self.operator["item"]
        for bad in ({**item, "servingGrams": 23},
                    {**item, "per100": {**item["per100"], "protein": -1}}):
            with self.assertRaises(ValueError):
                collect_operators([self.feed], get=lambda _: {"schemaVersion": 1, "entries": [
                    {**self.operator, "item": bad}
                ]})

    def test_writes_equivalent_json_and_sqlite(self):
        row = open_food_facts(self.product, "Coles", "2026-11-19")
        with TemporaryDirectory() as tmp:
            output = Path(tmp)
            write_snapshot(output, "supermarkets", [row])
            self.assertEqual(json.loads((output / "supermarkets.json").read_text())["entries"], [row])
            with sqlite3.connect(output / "supermarkets.sqlite") as db:
                stored = db.execute("SELECT retailer, payload FROM nutrition WHERE barcode = ?",
                                    (self.product["code"],)).fetchone()
                self.assertEqual(stored[0], "Coles")
                self.assertEqual(json.loads(stored[1]), row["item"])
