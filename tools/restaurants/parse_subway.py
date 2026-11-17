import re, sys, json
lines = open(sys.argv[1]).read().splitlines()
stop = next(i for i, l in enumerate(lines) if 'AVG QTY Per 100g' in l)
lines = lines[:stop]
HEADERS = [("Subway 6-Inch® Subs", None), ("Wraps (on regular", "Wraps (regular)"), ("Wraps (on large", "Wraps (large)"),
           ("Salads (regular", "Salads (regular)"), ("Salads (large", "Salads (large)"), ("Mini Subs", "Mini subs"),
           ("Breakfast Wraps", "Breakfast wraps"), ("Breakfast", "BREAKFAST"), ("Sides & Snacks", "Sides and snacks"),
           ("Cookies", "Cookies"), ("Smoothies", "Smoothies"), ("Breads", "Breads and wraps (on their own)"),
           ("Meat, Poultry", "Fillings (amount on a 6-inch sub)"), ("Sauces & Dressings", "Sauces and dressings"),
           ("Cheeses", "Cheeses"), ("Vegetables", "Vegetables"), ("Toppings", "Toppings"), ("Seasonings", "Seasonings")]
IGNORE = re.compile(r'^(Dietary Fiber|Serving Size|Energy|Sodium|Fat, Total|Sat\. Fat|Protein|Sugars|Carb\.|AVG QTY|Double values|values$|Values include|onion, capsicum|AUSTRALIA NUTRITION|May 2026|Seafood Origin|Amount on)')
NUMS = re.compile(r'((?:\s+\d[\d,]*\.?\d*){10})\s*$')
cat, pending, depth, items, breakfast = None, None, 0, [], False
for raw in lines:
    s = raw.strip()
    if not s: continue
    m = NUMS.search(raw)
    text = raw[:m.start()].strip() if m else s
    if depth == 0 and not m:
        h = next((h for h in HEADERS if s.startswith(h[0])), None)
        if h:
            if h[1] == "BREAKFAST": breakfast = True; cat = "Breakfast subs"; continue
            if h[1] is None: cat = "Breakfast subs" if breakfast else "6-inch subs"; continue
            cat = h[1]; breakfast = h[1] == "Breakfast wraps"; continue
        if IGNORE.match(s): continue
    if text.startswith('(') or depth > 0:
        depth += text.count('(') - text.count(')')
        depth = max(depth, 0)
    elif text and not IGNORE.match(text):
        pending = text
    if m:
        v = [float(x.replace(',', '')) for x in m.group(1).split()]
        if not pending: print('NO NAME', raw); continue
        items.append({'category': cat, 'name': pending, 'v': v}); pending = None
json.dump(items, open(sys.argv[2], 'w'), indent=0)
import collections; print(len(items), collections.Counter(i['category'] for i in items))
for i in items[:3] + items[60:63]: print(i)
