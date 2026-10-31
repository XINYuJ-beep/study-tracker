import json
Q='/home/ubuntu/study-tracker/assets/data/questions.json'
B='/tmp/exp/out/b04.jsonl'
rows=[json.loads(l) for l in open(B,encoding='utf-8') if l.strip()]
d=json.load(open(Q,encoding='utf-8'))
m=dict((r['id'],r['mcq']) for r in rows)
hit=0
for q in d['mcq']:
    if q['id'] in m:
        q['explain']=m[q['id']]
        hit+=1
open(Q,'w',encoding='utf-8').write(json.dumps(d,ensure_ascii=False,indent=1)+'\n')
d2=json.load(open(Q,encoding='utf-8'))
print('hit',hit,'mcq',len(d2['mcq']),'recall',len(d2['recall']),'keys',sorted(d2.keys()))
