# -*- coding: utf-8 -*-
# point_id 重配：每题在同一天 6 个考点中选文本匹配度最高者
# 规则：
#  1. 只在同一天 (item_id) 的考点内选
#  2. 原 point_id 若已是最高分且无并列 > 自己，则不改
#  3. 出现并列最高时，若原 point_id 在并列集合里，保留原样（不动）
#  4. 文本完全无匹配(best=0)时不动
import json, os, re, glob, sys
from collections import defaultdict, Counter

SK = 'tools/points'
STOP = {'什么', '如何', '怎么', '为什么', '下面', '关于', '说法', '正确', '的是', '以下', '哪个', '哪些', '区别', '区别是'}


def core(t):
    toks = re.findall(r'[A-Za-z][A-Za-z0-9\-\.]{1,}|[\u4e00-\u9fa5]{2,}', t or '')
    out = []
    for x in toks:
        if x in STOP:
            continue
        if re.fullmatch(r'[\u4e00-\u9fa5]{4,}', x):
            out.append(x)
            out.append(x[:2])
        else:
            out.append(x)
    return out


def hitn(text, topic):
    ts = core(topic)
    if not ts:
        return 0, 0
    return sum(1 for x in set(ts) if x in text), len(set(ts))


def load_pts():
    pts = {}
    for f in sorted(glob.glob(os.path.join(SK, 'm*.json'))):
        d = json.load(open(f, encoding='utf-8'))
        items = d.get('items') if isinstance(d, dict) else None
        if not items:
            continue
        for k, v in items.items():
            if not isinstance(v, dict):
                continue
            for p in v.get('points', []) or []:
                if isinstance(p, dict) and p.get('id'):
                    pts[p['id']] = {'day': k, 'topic': p.get('topic', '')}
    return pts


def load(p):
    return [json.loads(l) for l in open(p, encoding='utf-8') if l.strip()]


def main(paths, apply=False):
    pts = load_pts()
    byday = defaultdict(list)
    for pid, v in pts.items():
        byday[v['day']].append(pid)
    for p in paths:
        rows = load(p)
        changed = []
        keep_tie = 0
        keep_zero = 0
        for r in rows:
            day = r['item_id']
            cand = byday.get(day, [])
            if not cand:
                continue
            text = r['q'] + ' ' + ' '.join(r['o']) + ' ' + r.get('e', '')
            sc = []
            for pid in cand:
                h, n = hitn(text, pts[pid]['topic'])
                sc.append((h / n if n else 0.0, h, pid))
            sc.sort(reverse=True)
            top = sc[0][0]
            if top <= 0:
                keep_zero += 1
                continue
            tied = [s[2] for s in sc if abs(s[0] - top) < 1e-9]
            old = r['point_id']
            if old in tied:
                keep_tie += 1
                continue
            newpid = tied[0]
            if newpid != old:
                changed.append((r['item_id'], old, newpid, sc[0][0], r['q'][:28]))
                if apply:
                    r['point_id'] = newpid
        print('=== %s  n=%d  changed=%d  keep_tie=%d  keep_zero=%d' % (p, len(rows), len(changed), keep_tie, keep_zero))
        for c in changed:
            print('   %s : %s -> %s  best=%.2f  Q=%s' % c)
        if apply:
            with open(p, 'w', encoding='utf-8') as f:
                for r in rows:
                    f.write(json.dumps(r, ensure_ascii=False) + '\n')
            print('   WROTE')


if __name__ == '__main__':
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    main(args, apply=('--apply' in sys.argv))
