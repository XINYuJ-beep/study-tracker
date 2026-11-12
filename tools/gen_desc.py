#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""为 points 骨架补 desc（考点说明正文），风格对齐 m06/m07 存量。

规格（从 m06/m07 实测反推）：
  长度 245-687 字，中位 363-386；段落 1-2 段（两段以 \n\n 分隔）
  第一段：定义/原理/与相邻概念边界/为什么重要
  第二段：工程实现（具体库函数与参数）+ 一个典型易错点

用法:
  python3 tools/gen_desc.py --module m08 --item w85d1      # 单 item（6 条）
  python3 tools/gen_desc.py --module m08 --week 85         # 一周（7 item）
  python3 tools/gen_desc.py --module m08 --all --resume    # 全模块
输出: 原地改写 tools/points/<module>.json（写前 .bak）
"""
import argparse
import json
import os
import shutil
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_bank as g

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
POINTS_DIR = os.path.join(ROOT, 'tools', 'points')
DESC_MIN, DESC_MAX = 180, 820
RETRY = 6
GAP = [0.0]        # 每请求后的间隔秒数，由 --gap 设置

SYS = (
    '你是中文 AI 工程方向的教学教材作者，为考点撰写说明正文。\n'
    '规则：\n'
    '1. 只输出一个 JSON 数组，形如 [{"id":"w85d1-p1","desc":"..."}]，不要解释、不要代码块标记。\n'
    '2. 每个 desc 控制在 260-480 字之间，分 1-2 段，两段之间用 \\n\\n 分隔。\n'
    '3. 第一段讲定义、核心原理、以及与相邻概念的边界区分。\n'
    '4. 第二段讲工程实现，必须落到具体的库名、函数名、参数名，并指出一个典型易错点。\n'
    '5. 中文与英文/数字相邻时两边各留一个空格，标点用中文全角，禁止出现 markdown 标题符号。\n'
    '6. 每个 id 必须原样对应，不得遗漏、不得新增。'
)


def build_prompt(module, item_key, points):
    lines = []
    lines.append('【课程模块】m%s' % module)
    lines.append('【所属单元】%s（第 %s 天）' % (item_key, item_key.split('d')[1]))
    lines.append('【需撰写说明的考点】')
    for p in points:
        lines.append('  - id=%s | 难度 L%s | 考点：%s' % (p['id'], p.get('level', 1), p['topic']))
    lines.append('')
    lines.append('请为以上每个考点各写一段说明正文，内容要有区分度，不能互相套用。')
    lines.append('只输出 JSON 数组，首元素格式：')
    lines.append('[{"id":"%s","desc":"..."}]' % points[0]['id'])
    return '\n'.join(lines)


def clean(d):
    t = (d or '').strip()
    t = t.replace('```json', '').replace('```', '').strip()
    t = t.replace('\r\n', '\n')
    return t


def gen_item(env, module, item_key, points):
    """为单个 item 的 6 个考点生成 desc，返回 {pid: desc} + 失败原因"""
    last = ''
    for attempt in range(1, RETRY + 1):
        try:
            text = g.call_llm(env, build_prompt(module, item_key, points), SYS)
        except Exception as ex:
            last = 'HTTP: %s' % ex
            s = str(ex)
            if '429' in s:
                time.sleep(25 + 5 * attempt)     # 限流：长退避
            elif '402' in s:
                time.sleep(20 + 5 * attempt)
            else:
                time.sleep(max(min(3 * attempt, 30), GAP[0]))
            continue
        finally:
            if GAP[0]:
                time.sleep(GAP[0])
        arr = g.parse_json_array(text)
        if not arr:
            last = 'JSON 解析失败: %s' % text[:100]
            time.sleep(1)
            continue
        got = {}
        for o in arr:
            if isinstance(o, dict) and o.get('id') and o.get('desc'):
                got[str(o['id']).strip()] = clean(o['desc'])
        want = [p['id'] for p in points]
        miss = [x for x in want if not got.get(x)]
        bad = [x for x in want if got.get(x) and not (DESC_MIN <= len(got[x]) <= DESC_MAX)]
        if not miss and not bad:
            return got, None
        last = '缺/越界: miss=%s bad=%s' % (miss, bad)
        time.sleep(1)
    return {}, last


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--module', required=True)
    ap.add_argument('--item')
    ap.add_argument('--week')
    ap.add_argument('--all', action='store_true')
    ap.add_argument('--resume', action='store_true')
    ap.add_argument('--workers', type=int, default=1)
    ap.add_argument('--gap', type=float, default=0.0, help='每次请求后的间隔秒数，规避并发限流')
    args = ap.parse_args()
    GAP[0] = max(0.0, args.gap)

    path = os.path.join(POINTS_DIR, '%s.json' % args.module)
    d = json.load(open(path, encoding='utf-8'))
    items = d['items']

    targets = []
    for k in sorted(items.keys()):
        if args.item and k != args.item:
            continue
        if args.week and not k.startswith('w%sd' % args.week):
            continue
        pts = items[k]['points']
        if args.resume and all((p.get('desc') or '').strip() for p in pts):
            continue
        targets.append(k)

    if not targets:
        print('无需处理（全部已有 desc 或未匹配）')
        return
    print('待处理 item 数：%d，共 %d 条 desc' % (len(targets), sum(len(items[k]['points']) for k in targets)))

    if not os.path.exists(path + '.bak'):
        shutil.copy2(path, path + '.bak')
    env = g.load_env()
    total_want = sum(len(items[x]['points']) for x in targets)
    done = [0]
    fail_all = []
    t0 = time.time()
    import threading
    lock = threading.Lock()

    def flush():
        """原子落盘：先写 .tmp 再 rename，避免中途被杀产生半截 JSON"""
        tmp = path + '.tmp'
        with open(tmp, 'w', encoding='utf-8') as f:
            json.dump(d, f, ensure_ascii=False, indent=1)
        os.replace(tmp, path)

    def run(k):
        pts = items[k]['points']
        got, err = gen_item(env, args.module, k, pts)
        return k, got, err

    def commit(k, got, err):
        if err:
            fail_all.append((k, err))
            print('FAIL %s -> %s' % (k, err), flush=True)
            return
        with lock:
            for p in items[k]['points']:
                p['desc'] = got[p['id']]
            done[0] += len(got)
            flush()
            print('OK   %s (%d/%d) 已落盘' % (k, done[0], total_want), flush=True)

    if args.workers <= 1:
        for k in targets:
            commit(*run(k))
    else:
        with ThreadPoolExecutor(max_workers=args.workers) as ex:
            futs = [ex.submit(run, k) for k in targets]
            for f in as_completed(futs):
                commit(*f.result())

    flush()
    print('=== 写入 %s：新增 %d 条 desc，失败 %d 个 item，用时 %.1fs ===' % (path, done[0], len(fail_all), time.time() - t0))
    for k, err in fail_all:
        print('  FAIL %s: %s' % (k, err))


if __name__ == '__main__':
    main()
