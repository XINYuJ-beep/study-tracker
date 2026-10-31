# -*- coding: utf-8 -*-
"""w1.jsonl 机械归一化器。

不做语义改写，只做四件可机械判定的事：
1. item_id / day 按行序强制重排：1-6 -> w1d1..，7-12 -> w1d2，... 37-42 -> w1d7，43-45 -> '' / day 0
2. answer 按固定轮转序列铺满，使 0/1/2/3 各约 11/11/12/11
3. explain 超 70 字按中文标点断句裁到 40~70
4. 选项超 26 字按逗号切片压到 <=26

用法:
    python3 tools/normalize_w1.py          # 预览
    python3 tools/normalize_w1.py --write  # 落盘
"""
import sys, json

SRC = 'tools/bank/w1.jsonl'

# 固定 answer 轮转序列（45 项），统计后 0:11 1:11 2:12 3:11
ANS_SEQ = [
    0, 1, 2, 3, 1, 2,
    3, 0, 1, 2, 3, 0,
    1, 2, 3, 0, 2, 1,
    3, 0, 1, 2, 0, 3,
    1, 2, 3, 0, 1, 2,
    3, 0, 1, 3, 0, 3,
    1, 2, 3, 0, 2, 1,
    0, 1, 2,
]

MAX_OPT = 24
MIN_OPT = 14
E_MIN, E_MAX, E_TARGET = 40, 80, 68


def fix_explain(s):
    s = (s or '').strip().replace('\n', '')
    if E_MIN <= len(s) <= E_MAX:
        return s
    if len(s) < E_MIN:
        return s  # 太短不动，交给校验器报错，不硬凑
    # 超长：按标点断句累积到 <= E_MAX 且尽量接近 E_TARGET
    segs, buf = [], ''
    for ch in s:
        buf += ch
        if ch in '。；！？':
            segs.append(buf)
            buf = ''
    if buf:
        segs.append(buf)
    out, done = '', False
    for seg in segs:
        if done:
            break
        cand = out + seg
        if len(cand) <= E_MAX:
            out = cand
        else:
            if len(out) >= E_MIN:
                done = True
            else:
                # 单句就超长，退化为按逗号切
                parts, b = [], ''
                for ch in seg:
                    b += ch
                    if ch in '，、':
                        parts.append(b)
                        b = ''
                if b:
                    parts.append(b)
                for p in parts:
                    if len(out + p) <= E_MAX:
                        out += p
                    else:
                        break
                done = True
    out = out.strip()
    return out if len(out) >= E_MIN else s[:E_MAX].rstrip('，、。；')


def fix_option(s):
    s = (s or '').strip()
    if len(s) <= MAX_OPT:
        return s
    # 按逗号切，保留能组成 <=MAX_OPT 且 >=MIN_OPT 的最长前缀
    parts, b = [], ''
    for ch in s:
        b += ch
        if ch in '，、；':
            parts.append(b)
            b = ''
    if b:
        parts.append(b)
    out = ''
    for p in parts:
        if len(out + p) <= MAX_OPT:
            out += p
        else:
            break
    out = out.rstrip('，、；')
    if len(out) < MIN_OPT:
        out = s[:MAX_OPT]
    return out


def norm_iid(idx, total):
    """idx 从 0 开始，total=45"""
    if idx >= 42:
        return '', 0
    day = idx // 6 + 1
    return 'w1d%d' % day, day


def main():
    rows = [json.loads(l) for l in open(SRC, encoding='utf-8') if l.strip()]
    assert len(rows) == 45, '行数不是 45: %d' % len(rows)

    out = []
    for i, r in enumerate(rows):
        iid, day = norm_iid(i, len(rows))
        a = ANS_SEQ[i]
        opts = [fix_option(o) for o in r['o']]
        # 保持答案项在正确位置：原正确答案文本移到 a 位
        old_a = r['a']
        right = opts[old_a]
        rest = [o for j, o in enumerate(opts) if j != old_a]
        new_opts = rest[:a] + [right] + rest[a:]
        e = fix_explain(r['e'])
        row = {
            'item_id': iid,
            'day': day,
            'q': r['q'].strip(),
            'o': new_opts,
            'a': a,
            'e': e,
        }
        out.append(row)
        flag = 'OK '
        if not (40 <= len(e) <= 80):
            flag = 'BAD'
        print('%s %2d %-5s a=%d q=%d lens=%s ratio=%.2f e=%d' % (
            flag, i + 1, iid or 'EXAM', a, len(row['q']), [len(o) for o in new_opts],
            max(len(o) for o in new_opts) / max(1, min(len(o) for o in new_opts)), len(e)))

    from collections import Counter
    c = Counter(r['a'] for r in out)
    print('answer 分布:', {k: c.get(k, 0) for k in range(4)})
    c2 = Counter(r['item_id'] for r in out)
    print('item_id 分布:', dict(c2))

    if '--write' in sys.argv:
        with open(SRC, 'w', encoding='utf-8') as f:
            f.write('\n'.join(json.dumps(r, ensure_ascii=False) for r in out) + '\n')
        print('已写入', SRC)
    else:
        print('预览模式，未写入')


if __name__ == '__main__':
    main()
