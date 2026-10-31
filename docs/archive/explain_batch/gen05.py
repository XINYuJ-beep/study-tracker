import json, os
base='/tmp/exp'
rows=[json.loads(l) for l in open(os.path.join(base,'m05.jsonl'),encoding='utf-8')]
ids=[r['id'] for r in rows]
txt={}
for line in open('/tmp/ex05.txt',encoding='utf-8'):
    line=line.strip()
    if not line:
        continue
    k,_,v=line.partition('|')
    txt[k.strip()]=v.strip()
out=[]
for i in ids:
    out.append({'id':i,'recall':'','mcq':txt.get(i,'')})
os.makedirs(os.path.join(base,'out'),exist_ok=True)
with open(os.path.join(base,'out','b05.jsonl'),'w',encoding='utf-8') as f:
    for o in out:
        f.write(json.dumps(o,ensure_ascii=False)+'\n')
ls=[len(o['mcq']) for o in out]
bad=[o['id'] for o in out if len(o['mcq'])<40 or len(o['mcq'])>80]
print('lines',len(out))
print('bad',bad)
print('min',min(ls),'max',max(ls),'avg',round(sum(ls)/len(ls),1))
print('ids_ok',ids==[r['id'] for r in rows])
print('text_ids',len([o for o in out if o['mcq']]))
print('start_ok',all(o['mcq'].startswith('答案是') for o in out if o['mcq']))
