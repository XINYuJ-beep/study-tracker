import json,statistics
p='/tmp/exp/out/b01.jsonl'
rows=[json.loads(l) for l in open(p) if l.strip()]
bad=[(r['id'],len(r['explain'])) for r in rows if not (40<=len(r['explain'])<=80)]
L=[len(r['explain']) for r in rows]
print('lines',len(rows),'bad',bad)
print('min',min(L),'max',max(L),'avg',round(statistics.mean(L),1))
print('ids_ok',[r['id'] for r in rows]==['q%03d'%i for i in range(1,37)])
print('start_ok',all(r['explain'].startswith('答案是') for r in rows))
