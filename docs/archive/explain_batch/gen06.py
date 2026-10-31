import json, os, re
base='/tmp/exp'
src=[json.loads(l) for l in open(f'{base}/m06.jsonl',encoding='utf-8')]
txt={}
for line in open('/tmp/ex06.txt',encoding='utf-8'):
    line=line.rstrip('\n')
    if not line.strip():
        continue
    i,s=line.split('|',1)
    txt[i.strip()]=s.strip()
out=[]
for r in src:
    i=r['id']
    out.append({'id':i,'recall':'','mcq':txt.get(i,'')})
os.makedirs(f'{base}/out',exist_ok=True)
with open(f'{base}/out/b06.jsonl','w',encoding='utf-8') as f:
    for r in out:
        f.write(json.dumps(r,ensure_ascii=False)+'\n')
bad=[]
ln=[]
for r in out:
    L=len(r['mcq'])
    ln.append(L)
    if L<40 or L>80:
        bad.append((r['id'],L))
print('lines',len(out))
print('bad',bad)
print('min',min(ln),'max',max(ln),'avg',round(sum(ln)/len(ln),1))
print('ids_ok',[r['id'] for r in out]==[r['id'] for r in src])
print('text_ids',len([r for r in out if r['mcq']]))
print('start_ok',all(r['mcq'].startswith('答案是') for r in out))
