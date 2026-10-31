import json
src='/tmp/exp/out/b08.jsonl'
dst='/home/ubuntu/study-tracker/assets/data/questions.json'
rows=[json.loads(l) for l in open(src) if l.strip()]
new={r['id']:r['mcq'] for r in rows}
d=json.load(open(dst))
print('topkeys',list(d.keys()),'mcq',len(d['mcq']),'recall',len(d['recall']))
hit=0
for t in d['mcq']:
    if t['id'] in new:
        t['explain']=new[t['id']]
        hit+=1
print('hit',hit,'mcq',len(d['mcq']),'recall',len(d['recall']))
json.dump(d,open(dst,'w'),ensure_ascii=False,indent=1)
print('written')
print('rc=0')
