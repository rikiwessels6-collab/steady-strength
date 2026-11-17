"""Checks the bundled AUSNUT 2023 generic foods (Resources/Foods/ausnut_2023.json)."""
import json
import unittest
from pathlib import Path

FILE = Path(__file__).resolve().parents[2] / "Resources" / "Foods" / "ausnut_2023.json"


class GenericFoods(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads(FILE.read_text())
        cls.foods = cls.data["foods"]

    def test_attribution_and_size(self):
        self.assertIn("Food Standards Australia New Zealand", self.data["source"])
        self.assertIn("Creative Commons Attribution 4.0", self.data["source"])
        self.assertGreater(len(self.foods), 3500)

    def test_ids_unique_and_core_values_present(self):
        ids = [f["id"] for f in self.foods]
        self.assertEqual(len(ids), len(set(ids)))
        for f in self.foods:
            for key in ("name", "kj", "p", "f", "c", "fi"):
                self.assertIn(key, f, f["id"])
                if key != "name":
                    self.assertGreaterEqual(f[key], 0, f["id"])

    def test_parts_make_sense(self):
        bad = [f["id"] for f in self.foods
               if f.get("sf", 0) > f["f"] + 0.05 or f.get("su", 0) > f["c"] + 0.05
               or f["p"] + f["f"] + f["c"] + f["fi"] > 105]  # published values overlap slightly in a few foods
        self.assertEqual(bad, [])

    def test_measures_are_real_portions(self):
        for f in self.foods:
            for m in f.get("measures", []):
                self.assertGreaterEqual(m["grams"], 1, f["id"])
                self.assertNotIn("density", m["label"], f["id"])

    def test_known_food(self):
        beer = next(f for f in self.foods if f["id"] == "F000996")
        self.assertEqual(beer["kj"], 174)
        self.assertIn({"label": "1 can", "grams": 332.97}, beer["measures"])


if __name__ == "__main__":
    unittest.main()
