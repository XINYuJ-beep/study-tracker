#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
周考点合并/校验工具  merge_week_points.py

用途：把某一周的考点文件 (tools/points/_wN.json) 校验后合并进 m01.json

考点文件硬约定（必须严格遵守，勿再写错）：
{
  "module": "01",
  "week": 5,
  "week_title": "Python 进阶与工具",
  "items": {
      "w5d1": {"form": "A", "points": [{"id":"w5d1-p1","topic":"...","desc":"...","level":1}, ...]},
      ...
  }
}

用法：
  python3 tools/merge_week_points.py tools/points/_w5.json          # 只校验
  python3 tools/merge_week_points.py tools/points/_w5.json --merge  # 校验+合并+清理
  python3 tools/merge_week_points.py tools/points/m01.json --verify  # 全量校验单一数据源
"""
import json, os, sys, shutil, tempfile

FIELDS = ('id', 'topic', 'desc')
LEVELS = (1, 2, 3)
FORMS = ('A', 'B', 'C')
PER_ITEM = 6


def die(msg):
    print('FAIL', msg)
    sys.exit(1)


def week_of(item_key):
    # 键形如 w5d3 -> '5'
    if not (item_key.startswith('w') and 'd' in item_key):
        die('非法 item 键名: %r' % item_key)
    return item_key[1:item_key.index('d')]


def verify_week(d, expect_points=None):
    """校验单周结构，返回 (ok, points)"""
    for k in ('module', 'week', 'week_title', 'items'):
        if k not in d:
            die('缺少顶层字段 %s' % k)
    items = d['items']
    if not isinstance(items, dict) or not items:
        die('items 必须是非空 dict')

    total = 0
    ids = []
    forms = []
    print('MODULE', d['module'], 'WEEK', d['week'], 'TITLE', d['week_title'])
    print('ITEMS', len(items))

    for k in sorted(items.keys(), key=lambda s: (int(week_of(s)), int(s[s.index('d') + 1:]))):
        v = items[k]
        # 结构断言：必须是 {form, points} 双键对象
        if not isinstance(v, dict):
            die('%s 必须是 dict，实际 %s' % (k, type(v).__name__))
        if 'points' not in v:
            die('%s 缺少 points 子键（考点列表必须挂在 points 下，不是裸列表）' % k)
        if 'form' not in v:
            die('%s 缺少 form 字段' % k)
        if v['form'] not in FORMS:
            die('%s form 非法: %r' % (k, v['form']))
        pl = v['points']
        if not isinstance(pl, list):
            die('%s points 必须是 list' % k)
        if len(pl) != PER_ITEM:
            die('%s 考点数 %d，要求 %d' % (k, len(pl), PER_ITEM))
        forms.append(v['form'])
        line = [k, v['form'], str(len(pl))]
        for p in pl:
            if not isinstance(p, dict):
                die('%s 内有非 dict 考点: %r' % (k, p))
            for f in FIELDS:
                if not p.get(f) or not str(p.get(f)).strip():
                    die('%s 考点 %r 字段 %s 为空' % (k, p.get('id'), f))
            if p.get('level') not in LEVELS:
                die('%s 考点 %s level 非法: %r' % (k, p['id'], p.get('level')))
            if not isinstance(p.get('id'), str):
                die('%s 考点 id 必须是字符串: %r' % (k, p.get('id')))
            ids.append(p['id'])
            line.append(p['id'])
        total += len(pl)
        print('  ' + ' '.join(map(str, line)))

    if len(set(ids)) != len(ids):
        dup = [i for i in set(ids) if ids.count(i) > 1]
        die('id 重复: %s' % dup)
    print('FORMS', '/'.join(forms))
    print('POINTS', total)
    if expect_points is not None and total != expect_points:
        die('总条数 %d != 预期 %d' % (total, expect_points))
    print('FIELDS_OK True')
    print('ID_UNIQUE True', len(ids))
    return total


def merge(week_file):
    w = json.load(open(week_file, encoding='utf-8'))
    verify_week(w, expect_points=len(w['items']) * PER_ITEM)

    src_path = 'tools/points/m01.json'
    src = json.load(open(src_path, encoding='utf-8'))
    src.setdefault('week_titles', {})[str(w['week'])] = w['week_title']
    for k, v in w['items'].items():
        if k in src['items']:
            die('%s 已存在于 m01.json，拒绝覆盖' % k)
        src['items'][k] = v

    # 原子写：先写临时文件再替换
    fd, tmp = tempfile.mkstemp(dir='tools/points', suffix='.tmp')
    os.close(fd)
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(src, f, ensure_ascii=False, indent=2)
    bak = src_path + '.bak'
    shutil.copy2(src_path, bak)
    os.replace(tmp, src_path)
    print('MERGED week', w['week'], '->', src_path)
    print('BAK', bak)
    verify_source(src_path)


def verify_source(path='tools/points/m01.json'):
    d = json.load(open(path, encoding='utf-8'))
    print('=== SOURCE', path, os.path.getsize(path), 'B ===')
    print('KEYS', list(d.keys()))
    print('WEEK_TITLES', json.dumps(d.get('week_titles', {}), ensure_ascii=False))
    items = d['items']
    per = {}
    total = 0
    ids = []
    for k, v in items.items():
        wk = week_of(k)
        if 'points' not in v:
            die('源文件 %s 缺少 points' % k)
        n = len(v['points'])
        per[wk] = per.get(wk, 0) + n
        total += n
        for p in v['points']:
            for f in FIELDS:
                if not p.get(f) or not str(p.get(f)).strip():
                    die('%s 字段 %s 空' % (k, f))
            if not isinstance(p.get('id'), str):
                die('%s 考点 id 必须是字符串: %r' % (k, p.get('id')))
            if p.get('level') not in LEVELS:
                die('%s level 非法' % p['id'])
            ids.append(p['id'])
    if len(set(ids)) != len(ids):
        die('源文件 id 重复')
    print('ITEMS', len(items))
    print('POINTS', total)
    print('PER_WEEK', dict(sorted(per.items(), key=lambda x: int(x[0]))))
    print('FIELDS_OK True')
    print('ID_UNIQUE True', len(ids))


if __name__ == '__main__':
    args = sys.argv[1:]
    if not args:
        die('用法见文件头 docstring')
    path = args[0]
    if '--merge' in args:
        merge(path)
    elif '--verify' in args:
        verify_source(path)
    else:
        verify_week(json.load(open(path, encoding='utf-8')),
                    expect_points=len(json.load(open(path, encoding='utf-8'))['items']) * PER_ITEM)
