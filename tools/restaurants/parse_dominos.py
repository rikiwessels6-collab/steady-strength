import re, html, json, sys
t = open(sys.argv[1]).read()
events = [(m.start(), 'range', html.unescape(m.group(1)).strip()) for m in re.finditer(r'class="nutritional-product-range">(.*?)</div>', t, re.S)]
cards = list(re.finditer(r'<div class="card" id="([^"]+)-nutritional-info-product-card" data-productservinginfo="([^"]*)"', t))
events += [(m.start(), 'card', m) for m in cards]
events.sort(key=lambda e: e[0])
items, rng = [], None
bounds = [m.start() for m in cards] + [len(t)]
for pos, kind, val in events:
    if kind == 'range': rng = val; continue
    m = val; code = m.group(1)
    seg = t[m.start(): bounds[bounds.index(m.start()) + 1]]
    data = json.loads(html.unescape(m.group(2)))
    # parameter names
    params = dict(re.findall(r'id="[^"]*-serving-parameter-([0-9a-f-]{36})" class="serving-info-name">(.*?)</span>', seg))
    servings = {j['Id']: j['Name'] for j in (json.loads(html.unescape(x)) for x in re.findall(r"data-servinginfo='([^']*)'", seg))}
    name = html.unescape(re.search(r'class="product-card-heading">(.*?)<', seg, re.S).group(1)).strip()
    unit_m = re.search(r'serving-parameter-value-b9d502c3-8752-43e3-bdb4-8ecb5ff5fcf3">[^<]*</span>\s*([A-Za-z]+)', seg)
    serv = re.search(r'id="' + re.escape(code) + r'-servings"[^>]*>(.*?)<', seg, re.S)
    per = {}
    for d in data:
        per.setdefault(d['ServingId'], {})[params.get(d['ServingParameterId'], d['ServingParameterId'])] = d['Value']
    for sid, vals in per.items():
        items.append({'range': rng, 'code': code, 'name': name, 'serving': servings.get(sid, '' if len(per) == 1 else sid),
                      'unit': unit_m.group(1) if unit_m else None, 'servings': html.unescape(serv.group(1)).strip() if serv else None, **vals})
json.dump(items, open(sys.argv[2], 'w'), indent=1)
print(len(items))
import collections
print(collections.Counter(i['range'] for i in items))
print(collections.Counter(k for i in items for k in i))
for i in items[:3] + items[-3:]: print(i)
