import re, sys, glob, json, os
FILES = {  # file -> (category, guide date)
 'Whopper-Beef': ('Burgers', '10 November 2026'), 'Chicken-Burgers': ('Chicken burgers', '10 November 2026'),
 'Breakfast': ('Breakfast', '10 November 2026'), 'Grill-Masters': ('Grill Masters', '30 June 2026'),
 'Plant-Based-Veggie': ('Plant-based and veggie', '23 January 2026'), 'Sides-Snacks': ('Sides and snacks', '26 September 2026'),
 'Extra-Condiments': ('Sauces and extras', '26 September 2026'), 'Jack-s-Cafe': ("Jack's Cafe", '26 September 2026'),
 'What-s-New': ("What's new", '26 September 2026'), 'Cold-Drinks': ('Cold drinks', '3 November 2026'),
 'Desserts': ('Desserts', '3 November 2026'), 'Frozen-Bursties': ('Frozen and Bursties', '3 November 2026'),
}
NUM = r'-?[\d,]*\.?\d+'
row = re.compile(r'^\s*(?P<name>.*?)\s{2,}(?:None\s+)?(?P<status>Permanent|LTO)\s+(?:Yes|No)\s+(?:Yes|No)\s+(?P<nums>.*)$')
out, problems = {}, []
def slug(s): return re.sub(r'[^a-z0-9]+', '-', s.lower().replace('’', '')).strip('-')
order = sorted(FILES, key=lambda k: 0)  # processed in dict order; newer guides win below
for key, (cat, date) in FILES.items():
    path = [p for p in glob.glob(sys.argv[1] + '/*.txt') if key in p]
    assert len(path) == 1, (key, path)
    lines = open(path[0]).read().splitlines()
    heading = None
    for i, ln in enumerate(lines):
        if ln.strip().startswith('Ingredients:'):
            j = i - 1
            while not lines[j].strip(): j -= 1
            heading = ' '.join(lines[j].split())
            continue
        m = row.match(ln)
        if not m: continue
        nums = re.findall(NUM, m.group('nums'))
        name = heading or ' '.join(m.group('name').split())
        if len(nums) != 15:
            problems.append((key, name, len(nums))); continue
        v = [float(x.replace(',', '')) for x in nums]
        size, kj = v[0], v[2]
        it = {'id': 'hj-' + slug(name), 'name': name.replace('’', "'"), 'category': cat, 'serveAmount': size,
              'unit': 'mL' if cat == 'Cold drinks' and False else 'g', 'servingDescription': None,
              'kj': kj, 'kcal': round(kj / 4.184), 'protein': v[4], 'fat': v[6], 'satFat': v[8], 'carbs': v[10],
              'sugar': v[12], 'sodium': v[14],
              'source': f"Hungry Jack's Australia official nutrition guide ({cat}, {date}), hungryjacks.com.au. Values per serve; kcal converted from kJ.",
              'checkedOn': '2026-11-17'}
        # Per-100 g x serve must give the per-serve figure: proves the columns were read correctly.
        scale = [(v[1], v[2]), (v[3], v[4]), (v[5], v[6]), (v[9], v[10])]
        it['_scaleOK'] = all(abs(a * size / 100 - b) <= max(1.0, b * 0.04) for a, b in scale)
        if m.group('status') == 'LTO': it['note'] = 'Limited-time item.'
        del it['servingDescription']
        if it['id'] in out:
            continue  # first (category guide) wins over "What's new" duplicates
        out[it['id']] = it
items = list(out.values())
ok, bad = [], []
MISMATCH = "Hungry Jack's published energy doesn't match its listed protein, fat and carbs; logged exactly as published."
for it in items:
    scale_ok = it.pop('_scaleOK')
    est = it['protein'] * 17 + it['fat'] * 37 + it['carbs'] * 17
    if not scale_ok or it['satFat'] > it['fat'] + 0.05 or it['sugar'] > it['carbs'] + 0.05 or it['serveAmount'] <= 0:
        bad.append((it['name'], 'columns' if not scale_ok else 'parts')); continue
    if abs(est - it['kj']) > max(it['kj'] * 0.15, 40):
        it['publishedMismatch'] = True
        it['note'] = (it.get('note', '') + ' ' + MISMATCH).strip()
    ok.append(it)
json.dump(ok, open(sys.argv[2], 'w'), indent=1)
print(len(ok), 'ok;', sum(1 for i in ok if i.get('publishedMismatch')), 'flagged;', 'excluded:', bad, 'unparsed:', problems)
