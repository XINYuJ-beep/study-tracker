# -*- coding: utf-8 -*-
# jsonl MCQ option shuffler v3
# seed key = (item_id, point_id, sha1(q)[:8])  逐题唯一
# 优化目标 = 全局答案均匀 + 逐天内部答案均匀
import json, sys, hashlib, random
from collections import Counter, defaultdict


def load(p):
    return [json.loads(l) for l in open(p, encoding='utf-8') if l.strip()]


def seedkey(r):
    h = hashlib.sha1(r['q'].encode('utf-8')).hexdigest()[:8]
    return '%s|%s|%s' % (r['item_id'], r['point_id'], h)


def shuffle_rows(rows, salt):
    out = []
    for r in rows:
        r2 = dict(r)
        o = list(r['o'])
        correct = o[r['a']]
        s = 'st:%s:%s' % (salt, seedkey(r))
        h = hashlib.sha256(s.encode('utf-8')).hexdigest()[:16]
        random.Random(int(h, 16)).shuffle(o)
        r2['o'] = o
        r2['a'] = o.index(correct)
        assert o[r2['a']] == correct, r['item_id']
        out.append(r2)
    return out


def cost(rows):
    g = Counter(r['a'] for r in rows)
    n = len(rows) / 4.0
    cg = sum((g.get(k, 0) - n) ** 2 for k in range(4))
    cc = 0.0
    byday = defaultdict(list)
    for r in rows:
        byday[r['item_id']].append(r['a'])
    for k, v in byday.items():
        c = Counter(v)
        m = len(v) / 4.0
        cc += sum((c.get(x, 0) - m) ** 2 for x in range(4))
    return cg * 20.0 + cc * 6.0, cg, cc


def balance(rows, limit=30000):
    best = None
    for salt in range(limit):
        cur = shuffle_rows(rows, salt)
        tot, cg, cc = cost(cur)
        if best is None or tot < best[0]:
            best = (tot, salt, cur, cg, cc)
        if cg < 0.01 and cc < 2.0:
            break
    return best


def perday(rows):
    d = defaultdict(list)
    for r in rows:
        d[r['item_id']].append(str(r['a']))
    return ' '.join('%s:%s' % (k, ''.join(v)) for k, v in sorted(d.items()))


def main(paths):
    for p in paths:
        rows = load(p)
        print('=== %s  n=%d' % (p, len(rows)))
        print('  before dist=', dict(sorted(Counter(r['a'] for r in rows).items())))
        print('  before dayseq:', perday(rows))
        tot, salt, new, cg, cc = balance(rows)
        new.sort(key=lambda r: (r['day'], r['point_id']))
        with open(p, 'w', encoding='utf-8') as f:
            for r in new:
                f.write(json.dumps(r, ensure_ascii=False) + '\n')
        print('  salt=%d total=%.3f gcost=%.3f dcost=%.3f' % (salt, tot, cg, cc))
        print('  after  dist=', dict(sorted(Counter(r['a'] for r in new).items())))
        print('  after  dayseq:', perday(new))


if __name__ == '__main__':
    main(sys.argv[1:])
