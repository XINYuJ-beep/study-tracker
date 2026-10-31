import json

src='/tmp/exp/out/b07.jsonl'
dst='/home/ubuntu/study-tracker/assets/data/questions.json'
rows=[json.loads(l) for l in open(src) if l.strip()]
new={r['id']:r['mcq'] for r in rows}
d=json.load(open(dst))
hit=0
for t in d['mcq']:
    if t['id'] in new:
        t['explain']=new[t['id']]
        hit+=1
json.dump(d,open(dst,'w'),ensure_ascii=False,indent=1)
print('hit',hit)
print('mcq',len(d['mcq']))
print('recall',len(d['recall']))
print('keys',sorted(d.keys()))
