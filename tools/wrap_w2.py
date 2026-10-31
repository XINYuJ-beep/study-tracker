#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 /tmp/w2_full.json（按天扁平 dict）包裹成 merge_week_points.py 认可的周文件结构。
目标结构：{module, week, week_title, items: {w1dX: {form, points:[{id,topic,desc,level}]}}}
form 一律沿用主库该 item 的 form。只换结构，不动 desc。
"""
import json, os

M = '/home/ubuntu/study-tracker/tools/points/m01.json'
SRC = '/tmp/w2_full.json'
DST = '/tmp/w2_week.json'
WEEK = 2
PER_ITEM = 6
FIELDS = ('id', 'topic', 'desc')

base = json.load(open(M, encoding='utf-8'))
flat = json.load(open(SRC, encoding='utf-8'))

bkeys = [k for k in base['items'] if k.startswith('w%d' % WEEK)]
print('BASE_ITEMS', len(bkeys), bkeys)

items = {}
prob = []
for k in bkeys:
    bform = base['items'][k].get('form')
    pts = flat.get(k)
    if pts is None:
        prob.append((k, 'MISSING_DAY'))
        continue
    if len(pts) != PER_ITEM:
        prob.append((k, 'COUNT', len(pts)))
    out = []
    for p in pts:
        if not isinstance(p, dict):
            prob.append((k, 'BAD_ELEM', type(p).__name__))
            continue
        if p.get('id') != k + '-p%d' % (len(out) + 1):
            prob.append((k, 'ID_SEQ', p.get('id')))
        for f in FIELDS:
            if not isinstance(p.get(f), str) or not p[f].strip():
                prob.append((k, 'EMPTY', p.get('id'), f))
        if p.get('level') not in (1, 2, 3):
            prob.append((k, 'LEVEL', p.get('id')))
        out.append({'id': p['id'], 'topic': p['topic'],
                    'desc': p['desc'], 'level': p['level']})
    items[k] = {'form': bform, 'points': out}

# 按 (week, day) 数值序重排
def dnum(k):
    return int(k.split('d')[-1])
items = {k: items[k] for k in sorted(items, key=dnum)}

allpts = [p for k in items for p in items[k]['points']]
ids = [p['id'] for p in allpts]
lens = [len(p['desc']) for p in allpts]

print('PROBLEMS', prob)
print('ITEMS', len(items))
print('POINTS', len(allpts))
print('UNIQ', len(set(ids)) == len(ids), len(set(ids)))
print('MIN', min(lens), 'MAX', max(lens), 'AVG', round(sum(lens) / len(lens), 1))
print('SHORT<160', [p['id'] for p in allpts if len(p['desc']) < 160])
print('SHORT<170', len([1 for p in allpts if len(p['desc']) < 170]))
print('ORDER_OK', [k for k in items] == sorted(items, key=dnum))
print('PER_ITEM', sorted(set(len(v['points']) for v in items.values())))

WT = base.get('week_titles', {})
week_title = WT.get(str(WEEK)) or WT.get('w%d' % WEEK) or WT.get('week%d' % WEEK) or ''
out = {'module': base.get('module', '01'), 'week': WEEK,
       'week_title': week_title, 'items': items}
print('WEEK_TITLE_INFER', json.dumps(out['week_title'], ensure_ascii=False))
print('BASE_WT_KEYS', list(base.get('week_titles', {}).keys())[:10])

if not prob and len(allpts) == len(bkeys) * PER_ITEM:
    json.dump(out, open(DST, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
    print('WROTE', DST, os.path.getsize(DST), 'B')
else:
    print('NOT_WRITTEN')
