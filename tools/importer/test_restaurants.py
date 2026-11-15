"""Checks the bundled restaurant menus (Resources/Restaurants/restaurants.json) for transcription mistakes."""
import json
import unittest
from pathlib import Path

FILE = Path(__file__).resolve().parents[2] / "Resources" / "Restaurants" / "restaurants.json"


class RestaurantMenus(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads(FILE.read_text())
        cls.items = [i for c in cls.data["chains"] for i in c["items"]]

    def test_ids_unique_and_fields_present(self):
        ids = [i["id"] for i in self.items]
        self.assertEqual(len(ids), len(set(ids)))
        for i in self.items:
            for key in ("name", "category", "serveAmount", "unit", "kj", "kcal", "protein", "fat", "carbs", "source"):
                self.assertIn(key, i, i["id"])
            self.assertIn(i["unit"], ("g", "mL"))
            self.assertGreater(i["serveAmount"], 0, i["id"])

    def test_kilojoules_match_calories(self):
        # Each guide prints both; a misread digit in either shows up here.
        for i in self.items:
            self.assertAlmostEqual(i["kj"] / 4.184, i["kcal"], delta=max(3, i["kcal"] * 0.02), msg=i["id"])

    def test_parts_make_sense(self):
        for i in self.items:
            self.assertLessEqual(i.get("satFat", 0), i["fat"] + 0.05, i["id"])
            self.assertLessEqual(i.get("sugar", 0), i["carbs"] + 0.05, i["id"])
            # Energy from protein, fat and carbohydrate is close to the total (within 15%).
            est = i["protein"] * 17 + i["fat"] * 37 + i["carbs"] * 17
            self.assertAlmostEqual(est, i["kj"], delta=i["kj"] * 0.15, msg=i["id"])


if __name__ == "__main__":
    unittest.main()
