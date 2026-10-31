import json, sys
src, dst = sys.argv[1], sys.argv[2]
S = json.load(open(src))
O = json.load(open('/tmp/w3_orig.json'))
base = {}
for wk in O.values() if isinstance(O, dict) else []:
    pass
if isinstance(O, dict):
    for k, v in O.items():
        if isinstance(v, list):
            for p in v:
                if isinstance(p, dict) and 'id' in p:
                    base[p['id']] = p
        elif isinstance(v, dict) and 'id' in v:
            base[k] = v
elif isinstance(O, list):
    for p in O:
        if isinstance(p, dict) and 'id' in p:
            base[p['id']] = p
print('BASE', len(base))
out = {}
for k, v in S.items():
    if isinstance(v, dict):
        out[k] = v
    elif isinstance(v, (list, tuple)):
        t, lv, d = v[0], v[1], v[2]
        out[k] = {'topic': t, 'level': lv, 'desc': d}
    else:
        b = base.get(k, {})
        out[k] = {'topic': b.get('topic', ''), 'level': b.get('level', 2), 'desc': v}
json.dump(out, open(dst, 'w'), ensure_ascii=False, indent=1)
print('WROTE_NORM', len(out))
