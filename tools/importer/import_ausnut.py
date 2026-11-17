#!/usr/bin/env python3
"""Builds Resources/Foods/ausnut_2023.json from the FSANZ AUSNUT 2023 workbooks.

Source (unchanged, in Resources/Source/AUSNUT/):
  AUSNUT 2023 - Food nutrient profiles.xlsx   values per 100 g
  AUSNUT 2023 - Food measures.xlsx            household measures (slice, cup, can...)

Licence: Creative Commons Attribution 4.0, (c) Food Standards Australia New Zealand.
Downloaded from foodstandards.gov.au/science-data/food-nutrient-databases/ausnut/data-files.

Values are copied as published; nothing is estimated. Output is deterministic.
Usage: python3 tools/importer/import_ausnut.py
"""
from __future__ import annotations

import json
from collections import defaultdict
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "Resources" / "Source" / "AUSNUT"
OUT = ROOT / "Resources" / "Foods" / "ausnut_2023.json"
CHECKED = "2026-11-17"
ATTRIBUTION = ("AUSNUT 2023, © Food Standards Australia New Zealand, "
               "used under Creative Commons Attribution 4.0. Values per 100 g as published.")
MAX_MEASURES = 6

# Column headings in the nutrient profiles sheet -> short output keys.
COLUMNS = {
    "Public food key": "key",
    "Food name": "name",
    "Energy with dietary fibre (kJ)": "kj",
    "Protein (g)": "p",
    "Total fat (g)": "f",
    "Available carbohydrate, with sugar alcohols (g)": "c",
    "Dietary fibre (g)": "fi",
    "Total sugars (g)": "su",
    "Total saturated fat (g)": "sf",
    "Sodium (Na) (mg)": "na",
}


def rnd(x: float) -> float:
    v = round(float(x), 2)
    return int(v) if v == int(v) else v


def header_row(ws, wanted: str):
    for i, row in enumerate(ws.iter_rows(min_row=1, max_row=10, values_only=True), start=1):
        cells = [str(c).strip() if c is not None else "" for c in row]
        if wanted in cells:
            return i, cells
    raise SystemExit(f"Couldn't find the '{wanted}' heading in {ws.title}")


def measure_label(qty, parts) -> str:
    q = rnd(qty) if qty is not None else 1
    words = [str(p).strip() for p in parts if p is not None and str(p).strip()]
    return f"{q} {words[0]}" + (f", {', '.join(words[1:])}" if len(words) > 1 else "")


def measures() -> tuple[dict[str, list], dict[str, float]]:
    wb = openpyxl.load_workbook(SRC / "AUSNUT 2023 - Food measures.xlsx", read_only=True)
    ws = wb.worksheets[-1]
    start, heads = header_row(ws, "Public food key")
    idx = {h.strip(): i for i, h in enumerate(heads) if h}
    k, qty, grams = idx["Public food key"], idx["Quantity"], idx["Gram amount"]
    desc = [i for h, i in idx.items() if h.startswith("Descriptor")]
    out: dict[str, list] = defaultdict(list)
    density: dict[str, float] = {}
    for row in ws.iter_rows(min_row=start + 1, values_only=True):
        if not row[k] or row[grams] is None:
            continue
        first = row[desc[0]]
        if first is not None and str(first).strip().lower() == "density":
            # "1 density": the gram amount is grams per millilitre (the volume column is blank or 0 for solids)
            if float(row[grams]) > 0 and (row[qty] in (None, 1)):
                density[row[k]] = rnd(float(row[grams]))
            continue  # a conversion factor, not a portion
        if first is None:
            continue
        g = float(row[grams])
        if g < 1:
            continue  # e.g. "1 seed": too small to be a useful portion
        label = measure_label(row[qty], [row[i] for i in desc])
        if len(out[row[k]]) < MAX_MEASURES and all(m["label"] != label for m in out[row[k]]):
            out[row[k]].append({"label": label, "grams": rnd(g)})
    return out, density


def main() -> None:
    wb = openpyxl.load_workbook(SRC / "AUSNUT 2023 - Food nutrient profiles.xlsx", read_only=True)
    ws = wb.worksheets[-1]
    start, heads = header_row(ws, "Public food key")
    idx = {}
    for h, key in COLUMNS.items():
        if h not in heads:
            raise SystemExit(f"Missing column: {h}")
        idx[key] = heads.index(h)
    portions, densities = measures()
    foods = []
    for row in ws.iter_rows(min_row=start + 1, values_only=True):
        if not row[idx["key"]]:
            continue
        food = {"id": str(row[idx["key"]]).strip(), "name": " ".join(str(row[idx["name"]]).split())}
        for key in ("kj", "p", "f", "c", "fi", "su", "sf", "na"):
            v = row[idx[key]]
            if v is not None and str(v).strip() != "":
                food[key] = rnd(v)   # blanks stay out (unknown), never zero
        if "kj" not in food:
            continue
        if food["id"] in densities:
            food["density"] = densities[food["id"]]   # g per mL, for drinks measured in mL
        if portions.get(food["id"]):
            food["measures"] = portions[food["id"]]
        foods.append(food)
    foods.sort(key=lambda f: f["id"])
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({"source": ATTRIBUTION, "checkedOn": CHECKED, "foods": foods},
                              ensure_ascii=False, separators=(",", ":")) + "\n")
    print(f"Wrote {len(foods)} foods to {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
