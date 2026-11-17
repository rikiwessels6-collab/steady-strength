import re, html, json, sys
t = open(sys.argv[1]).read()
t = re.sub(r'<script.*?</script>|<style.*?</style>', '', t, flags=re.S)
def clean(s): return ' '.join(html.unescape(re.sub(r'<[^>]+>', ' ', s)).split())
# Walk headings and tables in order
tokens = [(m.start(), 'h', clean(m.group(1))) for m in re.finditer(r'<h[2-4][^>]*>(.*?)</h[2-4]>', t, re.S)]
tokens += [(m.start(), 't', m.group(0)) for m in re.finditer(r'<table.*?</table>', t, re.S)]
tokens.sort()
SRC = "THISBOWL (formerly Fishbowl) Australia, Nutritional overview as of June 2026 (thisbowl.com/en-au). Values per serve as prepared; bowls on brown rice and cabbage unless noted."
def slug(s): return re.sub(r'[^a-z0-9]+', '-', s.lower()).strip('-')
heading, raw, items, bad, ids = None, [], [], [], set()
for _, kind, val in tokens:
    if kind == 'h': heading = val; continue
    rows = [[clean(c) for c in re.findall(r'<t[hd][^>]*>(.*?)</t[hd]>', r, re.S)] for r in re.findall(r'<tr.*?</tr>', val, re.S)]
    head = [h.lower() for h in rows[0]]
    for r in rows[1:]:
        if not r or not any(r): continue
        raw.append({'section': heading, 'cols': rows[0], 'row': r})
        d = dict(zip(head, r))
        def num(k, unit):
            m = re.search(r'([\d.,]+)\s*' + unit, d.get(k, ''))
            return float(m.group(1).replace(',', '')) if m else None
        kj = num('energy', 'kJ'); kcal = num('energy', 'Cal')
        name = d.get('menu item', r[0]) + (f", {d['size']}" if d.get('size', '').strip('–- ') else '')
        vals = dict(kj=kj, kcal=kcal, protein=num('protein', 'g'), fat=num('fat', 'g'), satFat=num('sat fat', 'g'),
                    carbs=num('carbohydrates', 'g'), sugar=num('sugar', 'g'), sodium=num('sodium', 'mg'))
        if 'allergens' in (heading or '').lower(): continue
        if any(vals[k] is None for k in ('kj', 'kcal', 'protein', 'fat', 'carbs')):
            bad.append((heading, name, 'missing values', r)); continue
        cat = re.sub(r'\s*nutrition information.*$', '', heading or 'Menu', flags=re.I)
        iid = 'thisbowl-' + slug(cat + ' ' + name)
        if iid in ids: bad.append((name, 'duplicate')); continue
        it = {'id': iid, 'name': name, 'category': cat, 'serveAmount': None, 'unit': 'serve',
              'servingDescription': f"1 {d['size'].lower()} serve" if d.get('size', '').strip('–- ') else '1 serve', **{k: v for k, v in vals.items() if v is not None},
              'source': SRC, 'checkedOn': '2026-11-17'}
        est = it['protein'] * 17 + it['fat'] * 37 + it['carbs'] * 17
        if abs(kj / 4.184 - kcal) > max(3, kcal * 0.02) or it.get('satFat', 0) > it['fat'] + .05 or it.get('sugar', 0) > it['carbs'] + .05:
            bad.append((name, kj, round(est))); continue
        if abs(est - kj) > max(kj * .15, 40):
            it['publishedMismatch'] = True
            it['note'] = "THISBOWL's published energy doesn't match its listed protein, fat and carbs; logged exactly as published."
        if '-allergens' in iid: continue
        ids.add(iid); items.append(it)
json.dump(items, open(sys.argv[2], 'w'), indent=1)
import collections
print(len(items), collections.Counter(i['category'] for i in items)); print('left out:', bad)
