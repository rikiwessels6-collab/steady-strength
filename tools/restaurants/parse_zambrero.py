import re, sys, json
L = open(sys.argv[1]).read().splitlines()
SRC = "Zambrero Australia, Nutritional Information, data correct as of 8 April 2026 (official guide). Values per serve, without sauce."
def slug(s): return re.sub(r'[^a-z0-9]+', '-', s.lower()).strip('-')
out, bad, seen = [], [], {}
for i, l in enumerate(L):
    if not l.strip().startswith('Choice of Filling:'): continue
    j = i - 1
    while not L[j].strip(): j -= 1
    title = ' '.join(L[j].split())
    fills = [f for f in re.split(r'\s{2,}', l.split(':', 1)[1].strip()) if f]
    unit = 'taco' if 'per taco' in L[i + 1] else 'serve'
    rows = {}
    for k in range(i + 2, i + 14):
        s = L[k].strip()
        key = ('kj' if s.endswith('kJ') or re.match(r'^\d+kJ', s) else 'kcal' if s.startswith('Energy') else
               'protein' if s.startswith('Protein') else 'fat' if s.startswith('Fat') else 'satFat' if s.startswith('saturated') else
               'carbs' if s.startswith('Carbohydrate') else 'sugar' if s.startswith('sugar') else 'sodium' if s.startswith('Sodium') else None)
        if key and key not in rows:
            tagged = re.findall(r"(\d[\d,]*(?:\.\d+)?)\s*(?:kJ|kcal|cal|g|mg)", s)
            loose = re.findall(r"(?<![\w.])(\d[\d,]*(?:\.\d+)?)(?=\s|kJ|kcal|g|mg|\)|$)", s)
            vals = tagged if len(tagged) == 2 * len(fills) else loose   # a few cells miss their unit
            rows[key] = [float(x.replace(",", "")) for x in vals]
    if len(rows) != 8 or any(len(v) != 2 * len(fills) for v in rows.values()):
        bad.append((title, 'grid', {k: len(v) for k, v in rows.items()}, len(fills))); continue
    base = title.replace('(without sauce)', '').replace('*', '').strip().title().replace("'S", "'s")
    for n, f in enumerate(fills):
        v = {k: rows[k][2 * n + 1] for k in rows}
        name = f"{base}, {f}"
        iid = 'zambrero-' + slug(name)
        it = {'id': iid, 'name': name, 'category': base, 'serveAmount': None, 'unit': 'serve',
              'servingDescription': f"1 {'taco' if unit == 'taco' else base.lower()}, without sauce",
              'kj': v['kj'], 'kcal': v['kcal'], 'protein': v['protein'], 'fat': v['fat'], 'satFat': v['satFat'],
              'carbs': v['carbs'], 'sugar': v['sugar'], 'sodium': v['sodium'], 'source': SRC, 'checkedOn': '2026-11-17'}
        est = it['protein'] * 17 + it['fat'] * 37 + it['carbs'] * 17
        problems = abs(it['kj'] / 4.184 - it['kcal']) > max(3, it['kcal'] * 0.02) or it['satFat'] > it['fat'] + 0.05 or it['sugar'] > it['carbs'] + 0.05 or abs(est - it['kj']) > max(it['kj'] * 0.15, 40)
        if iid in seen:
            if seen[iid] != {k: it[k] for k in ('kj', 'protein', 'fat', 'carbs')}: bad.append((name, 'appears twice with different values'))
            continue
        seen[iid] = {k: it[k] for k in ('kj', 'protein', 'fat', 'carbs')}
        if problems: bad.append((name, it['kj'], round(est))); continue
        out.append(it)
json.dump(out, open(sys.argv[2], 'w'), indent=1)
import collections
print(len(out), collections.Counter(i['category'] for i in out)); print('left out:', bad)
