import json, os
base='/tmp/exp'
rows=[json.loads(l) for l in open(os.path.join(base,'m04.jsonl'),encoding='utf-8')]
ids=[r['id'] for r in rows]
txt={}
for line in open('/tmp/ex04.txt',encoding='utf-8'):
    line=line.rstrip('\n')
    if not line.strip(): continue
    i,_,t=line.partition('|')
    txt[i.strip()]=t.strip()
out=[]
for i in ids:
    out.append({'id':i,'recall':'','mcq':txt.get(i,'')})
os.makedirs(os.path.join(base,'out'),exist_ok=True)
with open(os.path.join(base,'out','b04.jsonl'),'w',encoding='utf-8') as f:
    for r in out:
        f.write(json.dumps(r,ensure_ascii=False)+'\n')
lens=[len(r['mcq']) for r in out]
bad=[r['id'] for r in out if not (40<=len(r['mcq'])<=80)]
print('lines',len(out))
print('bad',bad)
print('min',min(lens),'max',max(lens),'avg',round(sum(lens)/len(lens),1))
print('ids_ok',[r['id'] for r in out]==ids)
print('text_ids',len(txt))
print('start_ok',all(r['mcq'].startswith('答案是') for r in out))
