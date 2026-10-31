import json
a=json.load(open('/tmp/q_before_b08.json'))
b=json.load(open('/home/ubuntu/study-tracker/assets/data/questions.json'))
A=a['mcq']; B=b['mcq']
ch=[(x['id'],y['id']) for x,y in zip(A,B) if x!=y]
print('changed',len(ch),'same',len(B)-len(ch))
print('recall_same',a['recall']==b['recall'])
print('ids_order_same',[x['id'] for x in A]==[x['id'] for x in B])
print('changed_ids',[c[0] for c in ch])
bad=[(x['id'],len(x['explain'])) for x in B if len(x['explain'])<40 or len(x['explain'])>80]
print('range_bad',bad)
L=[len(x['explain']) for x in B]
print('all_min',min(L),'all_max',max(L))
