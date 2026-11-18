"""KFC Australia: the website's Nutrition & Allergen page, saved from Safari as a PDF and run through
`pdftotext -layout`. The page lists energy (kJ) per serve for every item; protein, fat and carbohydrate
only appear in each item's "More Info" panel. Items whose panel has been transcribed (FULL below, from
screenshots of that panel) get full values; the rest are kept as energy only (`energyOnly: true`) and the
app says so. Nothing is estimated: kcal is the published kJ divided by 4.184.

usage: parse_kfc.py <kfc.txt> <items.json>
"""
import collections
import json
import re
import sys

CATS = ["HAPPIER HOURS", "NEW KWENCH BY KFC", "FEATURED OFFERS", "BURGERS", "BOXED MEALS", "CHICKEN", "SNACK HACKS",
        "PROTEIN PICKS", "SHARED MEALS", "TWISTERS & BOWLS", "GO BUCKETS & KIDS MEALS", "EVERYDAY VALUE",
        "SIDES & DESSERTS", "SWEET TREATS", "COLD DRINKS"]
SRC = "KFC Australia, Nutrition & Allergen Guide on kfc.com.au, information correct as at February 2026. Values per serve as published."
CHECKED = "2026-11-18"
ENERGY_NOTE = "Calories only. KFC shows protein, carbs and fat one item at a time on its website, so they aren't included and count as zero."

# Transcribed from the item's "More Info" panel, Per Serve: grams, kJ, protein, fat, sat fat, carbs, sugars, sodium mg.
FULL = {
    "Original Crispy Burger": (183, 1874, 24.7, 22.3, 2.1, 35.9, 4.3, 776),
}


def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower().replace("®", "").replace("™", "")).strip("-")


def clean(name):
    name = re.sub(r"^\$\d+(\.\d+)?\s+", "", name)      # prices change
    name = re.sub(r"^NEW\s+", "", name)
    return name.replace(" - Until 4pm", "").strip()


def main(src, dst):
    cat, items, seen, skipped = None, [], set(), []
    for line in open(src, encoding="utf-8").read().splitlines():
        for c in CATS:
            if re.search(r"\s{10,}" + re.escape(c) + r"\s*$", line):
                cat = c
        m = re.match(r"^\s+(.+?)\s{3,}(\d+|-)\s+More Info\s*$", line)
        if not (m and cat):
            continue
        raw, energy = m.group(1).strip(), m.group(2)
        if energy == "-":
            skipped.append((raw, "no energy listed"))
            continue
        name = clean(raw)
        if name in seen:          # some items appear under several headings
            continue
        seen.add(name)
        kj = float(energy)
        category = cat.title().replace("Kfc", "KFC").replace("New Kwench By", "Kwench by")
        it = {"id": "kfc-" + slug(name), "name": name, "category": category, "serveAmount": None, "unit": "serve",
              "servingDescription": "1 " + ("combo, regular size" if "Combo" in name else "serve as sold"),
              "kj": kj, "kcal": float(round(kj / 4.184)), "protein": None, "fat": None, "carbs": None,
              "source": SRC, "checkedOn": CHECKED}
        if name in FULL:
            g, fkj, p, f, sf, c, su, na = FULL[name]
            assert fkj == kj, name
            it.update(serveAmount=float(g), unit="g", servingDescription=None, protein=p, fat=f, satFat=sf,
                      carbs=c, sugar=su, sodium=float(na))
            it["source"] = SRC.replace("Values per serve", "Values per serve from the item's More Info panel")
        else:
            it["energyOnly"] = True
            it["note"] = ENERGY_NOTE
        items.append(it)
    json.dump(items, open(dst, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    print(len(items), collections.Counter(i["category"] for i in items))
    print("left out:", skipped)


if __name__ == "__main__":
    main(*sys.argv[1:])
