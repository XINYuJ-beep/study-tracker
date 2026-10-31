#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""全库十项体检：ITEMS/POINTS/UNIQ/MINLEN/SHORT/PER/ORDER_OK/PTS_SORT_OK/TOPIC_MISS/LEV_BAD

用法：
  python3 tools/audit_points.py                 # 体检 tools/points/m01.json
  python3 tools/audit_points.py <path>          # 体检指定模块文件
"""
import json
import os
import sys

MIN_LEN = 160          # desc 硬下限
SRC = sys.argv[1] if len(sys.argv) > 1 else 'tools/points/m01.json'
FORMS = ('A', 'B', 'C')
LEVELS = (1, 2, 3)


def key_order(k):
    return (int(k[1:k.index('d')]), int(k.split('d')[-1]))


def main():
    d = json.load(open(SRC, encoding='utf-8'))
    print('=== AUDIT', SRC, os.path.getsize(SRC), 'B ===')
    items = d['items']
    keys = list(items.keys())
    print('ITEMS', len(keys))
    print('KEYS_HEAD', keys[:3], '...', keys[-3:])

    # ORDER_OK
    print('ORDER_OK', keys == sorted(keys, key=key_order))

    total = 0
    ids = []
    per_week = {}
    short = []          # 全局短板
    short_by_week = {}
    minlen = 10 ** 9
    minwho = None
    pts_sort_bad = []
    topic_miss = []
    lev_bad = []
    form_bad = []

    for k in keys:
        v = items[k]
        week = k[1:k.index('d')]
        if v.get('form') not in FORMS:
            form_bad.append((k, v.get('form')))
        pts = v.get('points', [])
        per_week[week] = per_week.get(week, 0) + len(pts)
        pids = [p.get('id') for p in pts]
        if pids != sorted(pids, key=lambda x: int(str(x).split('-p')[-1])):
            pts_sort_bad.append(k)
        for i, p in enumerate(pts):
            total += 1
            pid = p.get('id')
            ids.append(pid)
            if not p.get('topic') or not str(p.get('topic')).strip():
                topic_miss.append(pid)
            if p.get('level') not in LEVELS:
                lev_bad.append((pid, p.get('level')))
            L = len(p.get('desc') or '')
            if L < minlen:
                minlen, minwho = L, pid
            if L < MIN_LEN:
                short.append((pid, L))
                short_by_week[week] = short_by_week.get(week, 0) + 1

    print('POINTS', total)
    print('UNIQ', len(set(ids)) == len(ids), len(set(ids)))
    print('PER_WEEK', dict(sorted(per_week.items(), key=lambda x: int(x[0]))))
    print('MINLEN', minlen, minwho)
    print('SHORT<%d' % MIN_LEN, len(short))
    print('SHORT_BY_WEEK', dict(sorted(short_by_week.items(), key=lambda x: int(x[0]))))
    if short:
        s = sorted(short, key=lambda x: x[1])[:12]
        print('SHORT_WORST12', s)
    print('ORDER_OK2', keys == sorted(keys, key=key_order))
    print('PTS_SORT_OK', not pts_sort_bad, pts_sort_bad[:10])
    print('TOPIC_MISS', topic_miss[:10], len(topic_miss))
    print('LEV_BAD', lev_bad[:10], len(lev_bad))
    print('FORM_BAD', form_bad[:10], len(form_bad))

    ok = (items and total and len(set(ids)) == len(ids)
          and not pts_sort_bad and not topic_miss and not lev_bad and not form_bad)
    print('VERDICT', 'PASS' if ok else 'FAIL')


if __name__ == '__main__':
    main()
