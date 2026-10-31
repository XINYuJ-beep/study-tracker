import json
rows=[json.loads(l) for l in open('/tmp/exp/m02.jsonl') if l.strip()]
d={}
bad=[]
for l in open('/tmp/ex02.txt', encoding='utf-8'):
    l=l.rstrip('\n')
    if not l.strip(): continue
    i,_,t=l.partition('|')
    d[i.strip()]=t.strip()
out=[]
for r in rows:
    t=d.get(r['id'])
    if t is None:
        print('MISSING', r['id']); continue
    out.append({'id':r['id'],'week':r['week'],'explain':t})
with open('/tmp/exp/out/b02.jsonl','w',encoding='utf-8') as f:
    for o in out:
        f.write(json.dumps(o,ensure_ascii=False)+'\n')
ls=[len(o['explain']) for o in out]
bad=[o['id'] for o in out if not (40<=len(o['explain'])<=80)]
print('lines',len(out))
print('bad',bad)
print('min',min(ls),'max',max(ls),'avg',round(sum(ls)/len(ls),1))
print('ids_ok', sorted([o['id'] for o in out])==sorted([r['id'] for r in rows]))
print('text_ids',len(d))
print('start_ok', out[0]['id']=='q037' and out[-1]['id']=='q072')
