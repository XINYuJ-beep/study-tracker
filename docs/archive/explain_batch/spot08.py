import json
d=json.load(open('assets/data/questions.json'))
m={x['id']:x for x in d['mcq']}
for q in ['q253','q262','q268','q271','q275','q276']:
    t=m[q]
    print(q,len(t['explain']),t['explain'][:40])
