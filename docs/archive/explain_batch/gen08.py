import json
src='/tmp/exp/m08.jsonl'
ex='/tmp/ex08.txt'
outd='/tmp/exp/out'
ids=[json.loads(l)['id'] for l in open(src) if l.strip()]
lines=[l.rstrip('\n') for l in open(ex) if l.strip()]
assert len(ids)==len(lines), (len(ids),len(lines))
out=[]
bad=[]
lens=[]
for qid,body in zip(ids,lines):
    n=len(body)
    lens.append(n)
    if n<40 or n>80:
        bad.append((qid,n))
    out.append({'id':qid,'recall':'','mcq':body})
print('bad',bad)
print('min',min(lens),'max',max(lens),'avg',round(sum(lens)/len(lens),1))
import os
os.makedirs(outd,exist_ok=True)
with open(outd+'/b08.jsonl','w') as f:
    for r in out:
        f.write(json.dumps(r,ensure_ascii=False)+'\n')
print('written',len(out))
