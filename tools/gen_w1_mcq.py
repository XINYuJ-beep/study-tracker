#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""W1 选择题生成器（P4 第 1 批）

数据源：tools/bank/w1.jsonl（每行一条 JSON）
配额：w1d1..w1d7 各 6 道 = 42 道 + W1 周综合卷 3 道（item_id='', day=0）= 45 道
id 区间：q277 - q321
默认只预览校验，加 --write 才落盘。
"""
import json
import sys
from collections import Counter

SRC = 'assets/data/questions.json'
BANK = 'tools/bank/w1.jsonl'
START_ID = 277
WEEK = 1
MODULE = '01'
TOTAL = 45
PER_ITEM = 6
EXAM = 3
DAY_RANGE = range(1, 8)

EXPLAIN_MIN, EXPLAIN_MAX = 40, 80
OPT_MAX = 28
LEN_RATIO_MAX = 2.0
ANS_SHARE_MIN, ANS_SHARE_MAX = 0.20, 0.30


def load_bank():
    rows = []
    with open(BANK, encoding='utf-8') as f:
        for ln, line in enumerate(f, 1):
            if not line.strip():
                continue
            try:
                rows.append((ln, json.loads(line)))
            except Exception as e:
                raise SystemExit('JSONL 第 %d 行解析失败: %s' % (ln, e))
    return rows


def load_existing():
    with open(SRC, encoding='utf-8') as f:
        data = json.load(f)
    return data


def validate(rows, existing_mcq):
    errs = []
    warns = []

    if len(rows) != TOTAL:
        errs.append('总量 %d != %d' % (len(rows), TOTAL))

    by_item = Counter()
    ans = Counter()
    seen_q = {}

    for idx, (ln, r) in enumerate(rows, 1):
        tag = '第%d行(%s)' % (ln, r.get('item_id') or 'EXAM')

        for k in ('item_id', 'day', 'q', 'o', 'a', 'e'):
            if k not in r:
                errs.append('%s 缺字段 %s' % (tag, k))
        if errs and errs[-1].startswith(tag):
            continue

        iid, day, q, opts, a, ex = r['item_id'], r['day'], r['q'], r['o'], r['a'], r['e']

        if not isinstance(iid, str):
            errs.append('%s item_id 非字符串' % tag)
        if not isinstance(day, int):
            errs.append('%s day 非整数' % tag)
        if not isinstance(a, int) or not (0 <= a <= 3):
            errs.append('%s answer=%r 不在 0..3' % (tag, a))
        if not isinstance(opts, list) or len(opts) != 4:
            errs.append('%s 选项数 %r != 4' % (tag, len(opts) if isinstance(opts, list) else opts))
            continue
        if len(set(opts)) != 4:
            errs.append('%s 选项存在重复' % tag)
        for oi, o in enumerate(opts):
            if not isinstance(o, str) or not o.strip():
                errs.append('%s 选项%d 为空' % (tag, oi))
            elif len(o) > OPT_MAX:
                errs.append('%s 选项%d 长度 %d > %d: %s' % (tag, oi, len(o), OPT_MAX, o))

        lens = [len(o) for o in opts]
        if min(lens) == 0:
            errs.append('%s 存在空选项，长度比无法计算' % tag)
        else:
            ratio = max(lens) / min(lens)
            if ratio > LEN_RATIO_MAX:
                errs.append('%s 选项长度比 %.2f > %.1f (lens=%s)' % (ratio and tag or tag, ratio, LEN_RATIO_MAX, lens))

        if not isinstance(ex, str):
            errs.append('%s explain 非字符串' % tag)
        else:
            n = len(ex.strip())
            if n < EXPLAIN_MIN or n > EXPLAIN_MAX:
                errs.append('%s explain 长度 %d 不在 %d~%d' % (tag, n, EXPLAIN_MIN, EXPLAIN_MAX))

        if not isinstance(q, str) or len(q.strip()) < 8:
            errs.append('%s 题干过短或非字符串' % tag)

        # 配额
        if iid == '':
            if day != 0:
                errs.append('%s 综合卷 day 必须为 0，实际 %r' % (tag, day))
        else:
            if iid not in ('w1d%d' % d for d in DAY_RANGE):
                errs.append('%s item_id 非法' % tag)
            if day != int(iid[3:]):
                errs.append('%s day=%r 与 item_id 不一致' % (tag, day))
        by_item[iid] += 1
        ans[a] += 1

        # 题干去重（本批内部 + 与存量）
        key = q.strip()
        if key in seen_q:
            errs.append('%s 题干与本批第%d行重复: %s' % (tag, seen_q[key], key[:20]))
        seen_q[key] = ln

    for d in DAY_RANGE:
        iid = 'w1d%d' % d
        if by_item[iid] != PER_ITEM:
            errs.append('%s 题量 %d != %d' % (iid, by_item[iid], PER_ITEM))
    if by_item[''] != EXAM:
        errs.append('综合卷题量 %d != %d' % (by_item[''], EXAM))

    # answer 分布
    for k in range(4):
        share = ans[k] / len(rows) if rows else 0
        if not (ANS_SHARE_MIN <= share <= ANS_SHARE_MAX):
            errs.append('answer=%d 占比 %.1f%% (%d 道) 不在 %.0f%%~%.0f%%' % (k, share * 100, ans[k], ANS_SHARE_MIN * 100, ANS_SHARE_MAX * 100))

    # 与存量交叉去重
    exist_q = set(x['question'].strip() for x in existing_mcq)
    for ln, r in rows:
        if r.get('q', '').strip() in exist_q:
            errs.append('第%d行 题干与存量题库重复: %s' % (ln, r['q'][:24]))

    return errs, warns, by_item, ans


def build(rows):
    out = []
    for i, (ln, r) in enumerate(rows):
        iid = r['item_id']
        out.append({
            'week': WEEK,
            'source_ref': iid if iid else 'w1exam',
            'id': 'q%03d' % (START_ID + i),
            'options': r['o'],
            'module': MODULE,
            'answer': r['a'],
            'explain': r['e'],
            'question': r['q'],
            'item_id': iid,
            'day': r['day'],
        })
    return out


def main():
    rows = load_bank()
    data = load_existing()
    existing_mcq = data['mcq']

    errs, warns, by_item, ans = validate(rows, existing_mcq)

    print('=== 校验报告 ===')
    print('题库条目: %d' % len(rows))
    print('按 item: %s' % dict(sorted(by_item.items())))
    print('answer 分布: %s' % {k: '%d (%.1f%%)' % (ans[k], ans[k] * 100.0 / max(len(rows), 1)) for k in range(4)})
    print('存量 mcq: %d -> 预计 %d' % (len(existing_mcq), len(existing_mcq) + len(rows)))
    print('id 区间: q%03d - q%03d' % (START_ID, START_ID + len(rows) - 1))

    if errs:
        print('\n=== 错误 %d 条 ===' % len(errs))
        for e in errs:
            print('  [E] ' + e)
        print('\n未写入。修复后重跑。')
        sys.exit(1)

    print('\n所有校验通过。')

    if '--write' not in sys.argv:
        print('预览模式，未写入。加 --write 落盘。')
        return

    new = build(rows)
    data['mcq'].extend(new)
    with open(SRC, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write('\n')
    print('已写入 %s：mcq %d -> %d' % (SRC, len(existing_mcq), len(data['mcq'])))


if __name__ == '__main__':
    main()
