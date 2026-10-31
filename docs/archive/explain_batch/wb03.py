import json
p='/home/ubuntu/study-tracker/assets/data/questions.json'
d=json.load(open(p,encoding='utf-8'))
rows=[json.loads(l) for l in open('/tmp/exp/out/b03.jsonl',encoding='utf-8') if l.strip()]
m=dict((r['id'],r['mcq']) for r in rows)
hit=0
for q in d['mcq']:
    if q['id'] in m:
        q['explain']=m[q['id']]
        hit+=1
open(p,'w',encoding='utf-8').write(json.dumps(d,ensure_ascii=False,indent=1)+'\n')
d2=json.load(open(p,encoding='utf-8'))
print('hit',hit)
print('mcq',len(d2['mcq']),'recall',len(d2['recall']))
print('keys',list(d2.keys()))
