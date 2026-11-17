import json, re, sys
raw = json.load(open(sys.argv[1]))
SRC = "Subway Australia, Nutrition Information, May 2026 (official guide, subway.com/en-AU). Values per serve; a Footlong is about double a 6-inch."
def slug(s): return re.sub(r'[^a-z0-9]+', '-', s.lower().replace('®', '')).strip('-')
items, bad, ids = [], [], set()
for r in raw:
    size, kj, kcal, p, f, sf, c, su, fi, na = r['v']
    name = r['name'].replace('®', '').replace(' *', '').strip()
    cat = r['category']
    iid = 'subway-' + slug(cat) + '-' + slug(name)
    if iid in ids: bad.append((cat, name, 'duplicate')); continue
    it = {'id': iid, 'name': name, 'category': cat, 'serveAmount': size, 'unit': 'g', 'kj': kj, 'kcal': kcal,
          'protein': p, 'fat': f, 'satFat': sf, 'carbs': c, 'sugar': su, 'sodium': na, 'source': SRC, 'checkedOn': '2026-11-17'}
    if cat.startswith('6-inch'): it['servingDescription'] = '6-inch sub'
    est = p * 17 + f * 37 + c * 17 + fi * 8
    if abs(kj / 4.184 - kcal) > max(3, kcal * 0.02) or sf > f + 0.05 or su > c + 0.05 or abs(est - kj) > max(kj * 0.15, 40):
        bad.append((cat, name, kj, round(est))); continue
    ids.add(iid); items.append(it)
json.dump(items, open(sys.argv[2], 'w'), indent=1)
print(len(items), 'ok; left out:', bad)
