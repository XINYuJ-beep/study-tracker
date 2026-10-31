import json

M = '/home/ubuntu/study-tracker/tools/points/m01.json'
m = json.load(open(M, encoding='utf-8'))

base = {}
src = {}
for k, v in m['items'].items():
    if k.startswith('w3d'):
        base[k] = [p['id'] for p in v['points']]
        for p in v['points']:
            src[p['id']] = (p['topic'], p['level'])

days = ['w3d%d' % i for i in range(1, 8)]
print('BASE_DAYS', sorted(base.keys()) == days)
print('BASE_COUNTS', {k: len(v) for k, v in base.items()})

merged = {}
for f in ('/tmp/w3_stage1.json', '/tmp/w3_stage2.json', '/tmp/w3_stage3.json'):
    d = json.load(open(f, encoding='utf-8'))
    for k, v in d.items():
        if k in merged:
            print('DUP_KEY', k)
        merged[k] = v

out = {}
prob = []
flat = []
for day in days:
    ids = base[day]
    lst = []
    miss = [pid for pid in ids if pid not in merged]
    if miss:
        prob.append((day, 'MISSING', miss))
        continue
    for pid in ids:
        elem = merged[pid]
        desc = elem['desc'] if isinstance(elem, dict) else elem
        bt, bl = src[pid]
        lst.append({'id': pid, 'topic': bt, 'desc': desc, 'level': bl})
    out[day] = lst
    flat.extend(lst)

print('PROBLEMS', prob)
print('TOTAL', len(flat))
print('SHORT', [(p['id'], len(p['desc'])) for p in flat if len(p['desc']) < 160])
print('QUOTE', [p['id'] for p in flat if '"' in p['desc']])
print('MIN', min(len(p['desc']) for p in flat), 'MAX', max(len(p['desc']) for p in flat))
print('FIELDS_OK', all(set(p.keys()) == {'id', 'topic', 'desc', 'level'} for p in flat))
print('IDS_COVER', len(flat) == 42 and len(set(p['id'] for p in flat)) == 42)
print('PER_DAY', {k: len(v) for k, v in out.items()})

if not prob and len(flat) == 42:
    json.dump(out, open('/tmp/w3_full.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print('WROTE /tmp/w3_full.json')
else:
    print('NOT_WRITTEN')