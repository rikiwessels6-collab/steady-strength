import json, re, sys
raw = json.load(open(sys.argv[1]))
SRC = "Domino's Pizza Australia, Nutritional Information & Allergens (dominos.com.au/nutrition), values per serve as published."
LESS = []
def num(v):
    v = (v or "").strip()
    if v.startswith('<'):
        LESS.append(v); return 0.0   # published as "less than"; counted as 0 and noted on the item
    return float(v) if v else None
def slug(s): return re.sub(r'[^a-z0-9]+', '-', s.lower()).strip('-')
items, skipped, ids = [], [], set()
for r in raw:
    if re.fullmatch(r'[0-9a-f-]{36}', r['serving'] or ''):
        skipped.append((r['name'], 'stale crust entry')); continue
    LESS.clear()
    vals = {k: num(r.get(src)) for k, src in [('size','Serving Size'),('kj','Energy (kilojoules)'),('kcal','Energy (Calories)'),('protein','Protein'),('fat','Fat - Total'),('satFat','Fat - Sat'),('carbs','Carbohydrate'),('sugar','Sugars'),('sodium','Sodium')]}
    if any(vals[k] is None for k in ('size','kj','kcal','protein','fat','carbs')):
        skipped.append((r['name'], r['serving'], 'missing values')); continue
    pizza = 'Pizza' in r['range']
    name = r['name'] + (f", {r['serving']}" if r['serving'] else '')
    m = re.match(r'(\d+) Serv', r['servings'] or '')
    n = int(m.group(1)) if m else None
    if pizza:
        if r['serving'] == 'Mini': n = 4   # the site's own rule: Mini pizzas have 4 serves
        desc = f"1 slice ({n} per pizza)" if n else "1 slice"
    else:
        desc = f"1 serve ({n} per pack)" if n and n > 1 else "1 serve"
    iid = 'dominos-' + slug(name)
    if iid in ids: skipped.append((name,'duplicate')); continue
    ids.add(iid)
    it = {'id': iid, 'name': name, 'category': r['range'], 'serveAmount': vals['size'], 'unit': 'g',
          'servingDescription': desc, 'kj': vals['kj'], 'kcal': vals['kcal'], 'protein': vals['protein'],
          'fat': vals['fat']}
    if vals['satFat'] is not None: it['satFat'] = vals['satFat']
    it['carbs'] = vals['carbs']
    if vals['sugar'] is not None: it['sugar'] = vals['sugar']
    if vals['sodium'] is not None: it['sodium'] = vals['sodium']
    if LESS: it['note'] = "The guide lists some values as less than 1 g; they're counted as 0."
    it['source'] = SRC; it['checkedOn'] = '2026-11-17'
    est = it['protein'] * 17 + it['fat'] * 37 + it['carbs'] * 17
    if (abs(it['kj'] / 4.184 - it['kcal']) > max(3, it['kcal'] * 0.02) or it.get('satFat', 0) > it['fat'] + 0.05
            or it.get('sugar', 0) > it['carbs'] + 0.05 or abs(est - it['kj']) > max(it['kj'] * 0.15, 40)):
        skipped.append((name, "published values don't add up; left out")); ids.discard(iid); continue
    items.append(it)
json.dump(items, open(sys.argv[2], 'w'), indent=1)
print(len(items), 'items;', 'skipped:', skipped)
