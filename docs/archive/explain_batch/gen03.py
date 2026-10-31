import json, io
src = [json.loads(l) for l in io.open('/tmp/exp/m03.jsonl', encoding='utf-8') if l.strip()]
ids = [r['id'] for r in src]
rows = []
for line in io.open('/tmp/ex03.txt', encoding='utf-8'):
    line = line.rstrip('\n')
    if not line.strip():
        continue
    i = line.find('|')
    rows.append((line[:i], line[i+1:]))
text_ids = [r[0] for r in rows]
ids_ok = text_ids == ids
start_ok = all(t.startswith('\u7b54\u6848\u662f') for _, t in rows)
lens = [len(t) for _, t in rows]
bad = [i for (i, t) in rows if not (40 <= len(t) <= 80)]
print('lines', len(rows))
print('bad', bad)
print('min', min(lens), 'max', max(lens), 'avg', round(sum(lens)/len(lens), 1))
print('ids_ok', ids_ok)
print('text_ids', len(text_ids))
print('start_ok', start_ok)
import os
os.makedirs('/tmp/exp/out', exist_ok=True)
with io.open('/tmp/exp/out/b03.jsonl', 'w', encoding='utf-8') as f:
    for i, t in rows:
        f.write(json.dumps({'id': i, 'recall': src[ids.index(i)].get('recall', ''), 'mcq': t}, ensure_ascii=False) + '\n')
print('written /tmp/exp/out/b03.jsonl')
