#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""QUOTE 清洗器：清掉 stage json 正文里的 ASCII 双引号。
两步：
  1) fix_code  把代码字面量改成单引号写法（语义等价，可运行）；
  2) fix_pair  把剩下成对的 ASCII 引号转中文引号。
用法：python3 tools/stage/fix_quote.py <src.json> <dst.json>
源目标必须分离，禁止同文件读写。
"""
import json
import re
import sys

Q = chr(34)
A = chr(39)
LQ = chr(0x201c)
RQ = chr(0x201d)

CODE_MAP = [
    ('x = ' + Q + 'hello' + Q, 'x = ' + A + 'hello' + A),
    (Q + '1' + Q + ' + 1', A + '1' + A + ' + 1'),
    ('input(' + Q + '\u5e74\u9f84\uff1a' + Q + ')', 'input(' + A + '\u5e74\u9f84\uff1a' + A + ')'),
    ('input().split(' + Q + ',' + Q + ')', 'input().split(' + A + ',' + A + ')'),
    ('f' + Q + '{name} \u4eca\u5e74 {age} \u5c81' + Q, 'f' + A + '{name} \u4eca\u5e74 {age} \u5c81' + A),
    ('f' + Q + '{price * qty:.2f}' + Q, 'f' + A + '{price * qty:.2f}' + A),
    (Q + '18' + Q, A + '18' + A),
]

CALL_RE = re.compile(
    r'([A-Za-z_][A-Za-z0-9_.]*)\(' + Q + r'([^' + Q + '\n]{0,60}?)' + Q + r'\)'
)

KEEP_CHARS = ('`', '(', '=', '{', '}', ')')


def fix_code(d):
    for a, b in CODE_MAP:
        d = d.replace(a, b)
    d = CALL_RE.sub(lambda m: m.group(1) + '(' + A + m.group(2) + A + ')', d)
    return d


def fix_pair(d):
    out = []
    i = 0
    n = len(d)
    while i < n:
        c = d[i]
        if c == '`':
            j = d.find('`', i + 1)
            if j < 0:
                out.append(d[i:])
                break
            out.append(d[i:j + 1])
            i = j + 1
            continue
        if c == Q:
            j = d.find(Q, i + 1)
            if j > i:
                seg = d[i + 1:j]
                ok = len(seg) < 40 and not any(x in seg for x in KEEP_CHARS)
                if ok:
                    out.append(LQ + seg + RQ)
                    i = j + 1
                    continue
        out.append(c)
        i += 1
    return ''.join(out)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    assert src != dst, 'src and dst must differ'
    S = json.load(open(src))
    for k, v in S.items():
        d = v['desc'] if isinstance(v, dict) else v
        d = fix_pair(fix_code(d))
        if isinstance(v, dict):
            v['desc'] = d
        else:
            S[k] = d
    left = [k for k in S if Q in (S[k]['desc'] if isinstance(S[k], dict) else S[k])]
    lens = [len(S[k]['desc'] if isinstance(S[k], dict) else S[k]) for k in S]
    print('COUNT', len(S))
    print('MIN', min(lens))
    print('MAX', max(lens))
    print('QUOTE_LEFT', left)
    print('CNQ', sum((S[k]['desc'] if isinstance(S[k], dict) else S[k]).count(LQ) for k in S))
    for k in left:
        d = S[k]['desc'] if isinstance(S[k], dict) else S[k]
        i = 0
        while True:
            i = d.find(Q, i)
            if i < 0:
                break
            print('  RESID', k, repr(d[max(0, i - 30):i + 30]))
            i += 1
    json.dump(S, open(dst, 'w'), ensure_ascii=False, indent=1)
    print('WROTE', dst)


if __name__ == '__main__':
    main()
