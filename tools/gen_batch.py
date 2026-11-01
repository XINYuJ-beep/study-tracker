#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""题库批量生成器（P4）

用法：
    python3 tools/gen_batch.py --week 2 --audit
    python3 tools/gen_batch.py --week 2 --write
    python3 tools/gen_batch.py --from 3 --to 12 --write --resume

数据源：
    tools/points/m0N.json        知识点骨架（item + 每 item 6 point）
    tools/bank/wN.jsonl          题料（缺失退出码 2）
    assets/data/questions.json   存量（交叉去重 + id 游标）

输出：
    assets/data/questions.json   追加
    tools/stage/gen_report_wN.log 校验报告
    tools/stage/gen_state.json    {"next_id":322,"done_weeks":[]}
"""
import argparse
import json
import os
import re
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'assets/data/questions.json')
STATE_PATH = os.path.join(ROOT, 'tools/stage/gen_state.json')
BANK_DIR = os.path.join(ROOT, 'tools/bank')
POINTS_DIR = os.path.join(ROOT, 'tools/points')
LOG_DIR = os.path.join(ROOT, 'tools/stage')

PER_ITEM = 6
EXAM = 3
EXPLAIN_MIN, EXPLAIN_MAX = 40, 80
OPT_MAX = 28
LEN_RATIO_MAX = 2.0
ANS_SHARE_MIN, ANS_SHARE_MAX = 0.20, 0.30
ANCHOR_MIN = 2

STOP = set('的 了 是 在 和 与 或 有 对 为 把 被 及 从 到 这 那 哪 什么 怎样 如何 下列 下面 说法 正确 错误 的是 可以 需要 必须 一个 一种 一条 一次 一台 一份 一项 以及 并且 但是 因为 所以 如果 那么 通常 主要 属于 哪些 哪个 多少 为什么 怎么 有关 关于'.split())


def module_of(week):
    return '0%d' % ((week - 1) // 12 + 1)


def points_path(week):
    return os.path.join(POINTS_DIR, 'm%s.json' % module_of(week))


def bank_path(week):
    return os.path.join(BANK_DIR, 'w%d.jsonl' % week)


def ngrams(s):
    t = set()
    for m in re.finditer(r'[A-Za-z][A-Za-z0-9_.\-]{1,}', s):
        t.add(m.group(0).lower())
    for m in re.finditer(r'[\u4e00-\u9fff]{2,}', s):
        seg = m.group(0)
        for L in (2, 3):
            for i in range(len(seg) - L + 1):
                t.add(seg[i:i + L])
    return t


def anchor_hit(question, point):
    tgt = ngrams((point.get('topic') or '') + ' ' + (point.get('desc') or ''))
    return set(w for w in (ngrams(question) & tgt) if len(w) >= 2 and w not in STOP)


def id_num(mid):
    return int(re.sub(r'\D', '', mid))


def last_id(mcq):
    return max(id_num(x['id']) for x in mcq) if mcq else 0


def load_src():
    with open(SRC, encoding='utf-8') as f:
        return json.load(f)


def load_points(week):
    p = points_path(week)
    if not os.path.exists(p):
        return None
    with open(p, encoding='utf-8') as f:
        return json.load(f)


def load_bank(week):
    p = bank_path(week)
    if not os.path.exists(p):
        return None
    rows = []
    with open(p, encoding='utf-8') as f:
        for ln, line in enumerate(f, 1):
            if line.strip():
                r = json.loads(line)
                if str(r.get('item_id', '')).endswith('exam'):
                    r['item_id'] = ''
                    r['day'] = 0
                rows.append((ln, r))
    return rows


def validate_week(week, rows, module_data, existing_mcq, anchor=True):
    errs = []
    items = module_data.get('items', {})
    pat = re.compile(r'w%dd[1-7]' % week)
    wk_items = sorted([k for k in items if pat.fullmatch(k)], key=lambda x: int(x.split('d')[1]))
    expect_total = len(wk_items) * PER_ITEM + EXAM
    if len(rows) != expect_total:
        errs.append('总量 %d != %d（%d item ×%d + %d）' % (len(rows), expect_total, len(wk_items), PER_ITEM, EXAM))
    by_item = Counter()
    ans = Counter()
    seen_q = {}
    exist_q = set((x.get('question') or '').strip() for x in existing_mcq)
    for ln, r in rows:
        iid = r.get('item_id', None)
        tag = '第%d行(%s)' % (ln, iid if iid else 'EXAM')
        miss = [k for k in ('item_id', 'day', 'q', 'o', 'a', 'e') if k not in r]
        if miss:
            errs.append('%s 缺字段 %s' % (tag, miss))
            continue
        day, q, opts, a, ex = r['day'], r['q'], r['o'], r['a'], r['e']
        if iid != '':
            if iid not in items:
                errs.append('%s item_id 不在 items 中' % tag)
            elif not pat.fullmatch(iid):
                errs.append('%s item_id %r 不属于 W%d' % (tag, iid, week))
        if anchor and iid and iid in items:
            pm = items[iid]['points']
            idx = by_item[iid]
            if idx < len(pm):
                hit = anchor_hit(q, pm[idx])
                if len(hit) < ANCHOR_MIN:
                    errs.append('%s 锚点不足(命中%d< %d) p%d: %s' % (tag, len(hit), ANCHOR_MIN, idx + 1, q[:26]))
        if not isinstance(opts, list) or len(opts) != 4:
            errs.append('%s 选项数 != 4' % tag)
            continue
        if len(set(opts)) != 4:
            errs.append('%s 选项重复' % tag)
        for oi, o in enumerate(opts):
            if not isinstance(o, str) or not o.strip():
                errs.append('%s 选项%d 为空' % (tag, oi))
            elif len(o) > OPT_MAX:
                errs.append('%s 选项%d 长度 %d > %d' % (tag, oi, len(o), OPT_MAX))
        lens = [len(o) for o in opts if isinstance(o, str) and o.strip()]
        if lens and min(lens) > 0 and max(lens) / min(lens) > LEN_RATIO_MAX:
            errs.append('%s 长度比 %.2f > %.1f' % (tag, max(lens) / min(lens), LEN_RATIO_MAX))
        if not isinstance(a, int) or not (0 <= a <= 3):
            errs.append('%s answer=%r 非法' % (tag, a))
        if not isinstance(ex, str) or not (EXPLAIN_MIN <= len(ex.strip()) <= EXPLAIN_MAX):
            errs.append('%s explain 长度 %s 不在 %d~%d' % (tag, len(ex.strip()) if isinstance(ex, str) else ex, EXPLAIN_MIN, EXPLAIN_MAX))
        if not isinstance(q, str) or len(q.strip()) < 8:
            errs.append('%s 题干过短' % tag)
        k = q.strip()
        if k in seen_q:
            errs.append('%s 题干批内重复(第%d行)' % (tag, seen_q[k]))
        seen_q[k] = ln
        if k in exist_q:
            errs.append('%s 题干与存量重复' % tag)
        if iid == '':
            if day != 0:
                errs.append('%s 周卷 day 必须为 0' % tag)
        else:
            if day != int(iid[-1]):
                errs.append('%s day=%r 与 item_id 不一致' % (tag, day))
        by_item[iid] += 1
        ans[a] += 1
    for k in wk_items:
        if by_item[k] != PER_ITEM:
            errs.append('%s 题量 %d != %d' % (k, by_item[k], PER_ITEM))
    if by_item[''] != EXAM:
        errs.append('周卷题量 %d != %d' % (by_item[''], EXAM))
    if rows:
        for k in range(4):
            share = ans[k] / len(rows)
            if not (ANS_SHARE_MIN <= share <= ANS_SHARE_MAX):
                errs.append('answer=%d 占比 %.1f%% 不在 20%%~30%%' % (k, share * 100))
    return errs, by_item, ans


def build_rows(week, rows, module, start_id):
    out = []
    for i, (ln, r) in enumerate(rows):
        iid = r['item_id']
        out.append({
            'week': week,
            'source_ref': iid if iid else 'w%dexam' % week,
            'id': 'q%03d' % (start_id + i),
            'options': r['o'],
            'module': module,
            'answer': r['a'],
            'explain': r['e'],
            'question': r['q'],
            'item_id': iid,
            'day': r['day'],
        })
    return out


def save_src(data):
    tmp = SRC + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write('\n')
    os.replace(tmp, SRC)


def save_state(state):
    os.makedirs(os.path.dirname(STATE_PATH), exist_ok=True)
    tmp = STATE_PATH + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(state, f, ensure_ascii=False, indent=1)
        f.write('\n')
    os.replace(tmp, STATE_PATH)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--week', type=int)
    ap.add_argument('--from', dest='wfrom', type=int)
    ap.add_argument('--to', dest='wto', type=int)
    ap.add_argument('--write', action='store_true')
    ap.add_argument('--resume', action='store_true')
    ap.add_argument('--audit', action='store_true')
    ap.add_argument('--no-anchor', action='store_true', help='关闭题干锚点校验（仅历史数据兼容用）')
    args = ap.parse_args()

    if args.week:
        weeks = [args.week]
    elif args.wfrom and args.wto:
        weeks = list(range(args.wfrom, args.wto + 1))
    else:
        ap.error('需要 --week 或 --from/--to')
    if len(weeks) > 10:
        print('单批 <= 10 周，当前 %d 周' % len(weeks))
        sys.exit(2)

    if not os.path.exists(STATE_PATH):
        data0 = load_src()
        state = {'next_id': last_id(data0['mcq']) + 1, 'done_weeks': []}
        save_state(state)
    else:
        with open(STATE_PATH, encoding='utf-8') as f:
            state = json.load(f)

    data = load_src()
    existing = data['mcq']
    cursor = state['next_id']
    lid = last_id(existing)
    if lid != cursor - 1:
        print('自愈校验失败：questions.json 末条 q%03d != next_id-1 (q%03d)，人工确认后修 gen_state.json' % (lid, cursor - 1))
        sys.exit(3)

    lines = []
    def emit(s):
        print(s)
        lines.append(s)

    ok_all = True
    for wk in weeks:
        if args.resume and wk in state['done_weeks']:
            emit('W%d 已完成，跳过' % wk)
            continue
        module_data = load_points(wk)
        if module_data is None:
            emit('W%d 缺 points 文件 %s，跳过' % (wk, points_path(wk)))
            ok_all = False
            continue
        rows = load_bank(wk)
        if rows is None:
            emit('W%d 缺题料 %s（退出码 2）' % (wk, bank_path(wk)))
            ok_all = False
            continue
        module = module_data.get('module', module_of(wk))
        errs, by_item, ans = validate_week(wk, rows, module_data, existing, anchor=not args.no_anchor)
        emit('=== W%d 校验报告（module %s）===' % (wk, module))
        emit('题料条数: %d' % len(rows))
        emit('按 item: %s' % dict(sorted(by_item.items())))
        emit('answer 分布: %s' % {k: '%d(%.1f%%)' % (ans[k], ans[k] * 100.0 / max(len(rows), 1)) for k in range(4)})
        emit('id 区间: q%03d - q%03d' % (cursor, cursor + len(rows) - 1))
        if errs:
            ok_all = False
            emit('错误 %d 条:' % len(errs))
            for e in errs:
                emit('  [E] ' + e)
        else:
            emit('全部校验通过')
        if args.write:
            if errs:
                emit('W%d 有错，未写入' % wk)
            else:
                new = build_rows(wk, rows, module, cursor)
                data['mcq'].extend(new)
                save_src(data)
                existing = data['mcq']
                state['next_id'] = cursor + len(rows)
                if wk not in state['done_weeks']:
                    state['done_weeks'].append(wk)
                save_state(state)
                emit('已写入：mcq -> %d，next_id -> %d，done_weeks=%s' % (len(existing), state['next_id'], state['done_weeks']))
                cursor = state['next_id']

    os.makedirs(LOG_DIR, exist_ok=True)
    tag = 'w%d' % weeks[0] if len(weeks) == 1 else 'w%d_%d' % (weeks[0], weeks[-1])
    lp = os.path.join(LOG_DIR, 'gen_report_%s.log' % tag)
    with open(lp, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')
    print('\n报告已写 %s' % lp)
    if not ok_all:
        sys.exit(1)


if __name__ == '__main__':
    main()
