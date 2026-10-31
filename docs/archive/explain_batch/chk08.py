import json,re,collections
rows=[json.loads(l) for l in open('/tmp/exp/out/b08.jsonl')]
bodies=[r['mcq'] for r in rows]
pre=collections.Counter(b[:3] for b in bodies)
print('prefix_kinds',len(pre))
print('prefix_counter',pre.most_common(5))
print('colon',[r['id'] for r in rows if '\uff1a' in r['mcq']])
print('dblspace',[r['id'] for r in rows if '  ' in r['mcq']])
print('dupchar',[r['id'] for r in rows if re.search(r'(.)\1\1',r['mcq']) and re.search(r'([\u4e00-\u9fa5])\1\1',r['mcq'])])
print('space_after_ans',sum(1 for b in bodies if b[3:4]==' '))
print('endswith',collections.Counter(b[-1] for b in bodies))
print('n',len(bodies))
