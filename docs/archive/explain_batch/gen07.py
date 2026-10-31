import json, re
base = '/tmp/exp'
rows = [json.loads(l) for l in open(base + '/m07.jsonl', encoding='utf-8') if l.strip()]
txt = {}
for line in open('/tmp/ex07.txt', encoding='utf-8'):
    line = line.rstrip('\n')
    if not line.strip():
        continue
    k, v = line.split('|', 1)
    txt[k.strip()] = v.strip()
out = []
bad = []
for r in rows:
    qid = r['id']
    body = txt.get(qid)
    if body is None:
        bad.append((qid, -1))
        continue
    n = len(body)
    if n < 40 or n > 80:
        bad.append((qid, n))
    out.append({'id': qid, 'recall': '', 'mcq': body})
with open(base + '/out/b07.jsonl', 'w', encoding='utf-8') as f:
    for o in out:
        f.write(json.dumps(o, ensure_ascii=False) + '\n')
ns = [len(txt[r['id']]) for r in rows if r['id'] in txt]
print('lines', len(out))
print('bad', bad)
print('min', min(ns) if ns else 0, 'max', max(ns) if ns else 0, 'avg', round(sum(ns)/len(ns), 1) if ns else 0)
print('ids_ok', [r['id'] for r in rows] == [o['id'] for o in out])
print('start_ok', out[0]['id'] == 'q217' and out[-1]['id'] == 'q252')
