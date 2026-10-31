import json

src=[json.loads(l) for l in open('/tmp/exp/out/b05.jsonl',encoding='utf-8')]
m=dict((r['id'],r['mcq']) for r in src)

p='/home/ubuntu/study-tracker/assets/data/questions.json'
d=json.load(open(p,encoding='utf-8'))
hit=0
for q in d['mcq']:
    if q['id'] in m:
        q['explain']=m[q['id']]
        hit+=1

s=json.dumps(d,ensure_ascii=False,indent=1)+'\n'
open(p,'w',encoding='utf-8').write(s)

d2=json.load(open(p,encoding='utf-8'))
print('hit',hit)
print('mcq',len(d2['mcq']))
print('recall',len(d2.get('recall',[])))
print('keys',sorted(d2.keys()))
