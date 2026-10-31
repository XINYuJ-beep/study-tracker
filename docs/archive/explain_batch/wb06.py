import json,sys
p='/home/ubuntu/study-tracker/assets/data/questions.json'
d=json.load(open(p,encoding='utf-8'))
src=[json.loads(l) for l in open('/tmp/exp/out/b06.jsonl',encoding='utf-8')]
m=dict((r['id'],r['mcq']) for r in src)
hit=0
for q in d['mcq']:
    if q['id'] in m:
        q['explain']=m[q['id']]
        hit+=1
print('hit',hit)
print('mcq',len(d['mcq']))
print('recall',len(d['recall']))
print('keys',sorted(d.keys()))
s=json.dumps(d,ensure_ascii=False,indent=1)+chr(10)
open(p,'w',encoding='utf-8').write(s)
sys.exit(0)
