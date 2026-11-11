#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""题料生成器：调 Claude 中转站按 points 产 wN.jsonl

用法:
  python3 tools/gen_bank.py --week 3            # 生成 W3 全部 45 题
  python3 tools/gen_bank.py --week 3 --resume   # 断点续跑
  python3 tools/gen_bank.py --week 3 --item w3d1  # 只生成某一天的 6 题

输出: tools/bank/w{N}.jsonl  (gen_batch.py 的输入)
凭据: /root/.study_llm.env
"""
import os
import sys
import json
import time
import argparse
import re as _re
import threading
import urllib.request
import urllib.error
# ---- 网络加固：强制 IPv4 + socket 默认超时（IPv6 到 CF 会挂死）----
import socket as _socket
_socket_hardened = True
_orig_gai = _socket.getaddrinfo
def _gai_v4(host, port, family=0, type=0, proto=0, flags=0):
    try:
        return _orig_gai(host, port, _socket.AF_INET, type, proto, flags)
    except Exception:
        return _orig_gai(host, port, family, type, proto, flags)
_socket.getaddrinfo = _gai_v4
_socket.setdefaulttimeout(120)
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENV_PATH = '/root/.study_llm.env'
POINTS_DIR = os.path.join(ROOT, 'tools', 'points')
BANK_DIR = os.path.join(ROOT, 'tools', 'bank')

EXAM_COUNT = 3
MAX_TOKENS = 16000
MAX_TOKENS_CAP = 32000
# 单次 HTTP 请求硬超时（秒）。配合 batch3.sh 的 timeout 双层兜底。
HTTP_TIMEOUT = 90
# 部分中转站前置 Cloudflare，会拦截 Python-urllib 默认 UA 返回 403/error code 1010，
# 必须伪装成常见浏览器 UA 才能通过。
UA = ('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')
RETRY = 7
# ---- 全局限速（中转站硬上限 5 req/min）----
RATE_LIMIT_PER_MIN = 600
_rate_lock = threading.Lock()
_rate_calls = []
def _rate_wait():
    """滑动窗口节流：保证任意 60s 内请求数 <= RATE_LIMIT_PER_MIN。"""
    while True:
        with _rate_lock:
            now = time.time()
            while _rate_calls and now - _rate_calls[0] > 60:
                _rate_calls.pop(0)
            if len(_rate_calls) < RATE_LIMIT_PER_MIN:
                _rate_calls.append(now)
                return
            wait = 60 - (now - _rate_calls[0]) + 0.5
        sys.stderr.write('[rate] 限速等待 %.1fs\n' % max(wait, 1.0))
        sys.stderr.flush()
        time.sleep(max(wait, 1.0))
R_OPTTOOSHORT = '选项过短(%d字): %s'
R_ENGLONG = '解析含连续英文长词'


def load_env(path=ENV_PATH):
    env = {}
    with open(path, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            k, v = line.split('=', 1)
            k = k.replace('export', '').strip()
            env[k] = v.strip().strip('"\'')
    for k in ('LLM_BASE', 'LLM_KEY', 'LLM_MODEL'):
        if k not in env:
            sys.exit('env 缺 %s: %s' % (k, path))
    return env


def module_of(week):
    if week <= 12:
        return 'm01'
    if week <= 24:
        return 'm02'
    if week <= 36:
        return 'm03'
    if week <= 48:
        return 'm04'
    if week <= 60:
        return 'm05'
    if week <= 72:
        return 'm06'
    if week <= 84:
        return 'm07'
    return 'm08'


def load_points(week):
    path = os.path.join(POINTS_DIR, module_of(week) + '.json')
    if not os.path.exists(path):
        sys.exit('缺 points 骨架: %s' % path)
    with open(path, encoding='utf-8') as f:
        data = json.load(f)
    items = data['items']
    prefix = 'w%dd' % week
    picked = {k: v for k, v in items.items() if k.startswith(prefix)}
    return picked


def _llm_protocol(base):
    """按 LLM_BASE 判定协议：含 /messages 走 Anthropic，否则走 OpenAI 兼容。"""
    b = (base or '').lower()
    if b.endswith('/messages'):
        return 'anthropic'
    return 'openai'


def call_llm(env, prompt, system):
    """调 LLM 取文本。openai/anthropic 双协议。
    推理模型（deepseek-flash 等）可能把 max_tokens 全烧在 reasoning_content 上，
    导致 content 为空。检测到此情况则把 max_tokens 翻倍重试，直到 CAP。"""
    base = env['LLM_BASE']
    proto = _llm_protocol(base)
    key = env['LLM_KEY']
    budget = MAX_TOKENS
    last_meta = ''
    while True:
        if proto == 'anthropic':
            body = {
                'model': env['LLM_MODEL'],
                'max_tokens': budget,
                'system': system,
                'messages': [{'role': 'user', 'content': prompt}],
            }
            headers = {
                'Content-Type': 'application/json',
                'x-api-key': key,
                'Authorization': 'Bearer ' + key,
                'anthropic-version': '2023-06-01',
                'User-Agent': UA,
            }
        else:
            body = {
                'model': env['LLM_MODEL'],
                'max_tokens': budget,
                'messages': [
                    {'role': 'system', 'content': system},
                    {'role': 'user', 'content': prompt},
                ],
            }
            headers = {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ' + key,
                'User-Agent': UA,
            }
        _rate_wait()
        req = urllib.request.Request(
            base,
            data=json.dumps(body).encode('utf-8'),
            headers=headers,
            method='POST',
        )
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as r:
            raw = r.read().decode('utf-8')
        data = json.loads(raw)
        finish = ''
        reason_len = 0
        if proto == 'anthropic':
            parts = data.get('content') or []
            text = ''.join(p.get('text', '') for p in parts if p.get('type') == 'text')
            finish = data.get('stop_reason') or ''
        else:
            ch = data.get('choices') or []
            text = ''
            if ch:
                msg = ch[0].get('message') or {}
                text = msg.get('content') or ''
                reason_len = len(msg.get('reasoning_content') or '')
                finish = ch[0].get('finish_reason') or ''
        text = text.strip()
        if text:
            return text
        # 空 content：判断是不是推理吃光了预算
        usage = data.get('usage') or {}
        rtk = (usage.get('completion_tokens_details') or {}).get('reasoning_tokens', 0)
        last_meta = 'finish=%s reasoning_tokens=%s reason_len=%s budget=%s' % (
            finish, rtk, reason_len, budget)
        if budget >= MAX_TOKENS_CAP:
            sys.stderr.write('[call_llm] 空响应且已到 max_tokens 上限: %s\n' % last_meta)
            return ''
        budget = min(budget * 2, MAX_TOKENS_CAP)
        sys.stderr.write('[call_llm] 空响应，token 翻倍重试: %s -> %s\n' % (last_meta, budget))


SYSTEM = (
    '你是中文编程教学题库作者。严格按用户给的考点写单选题。\n'
    '铁规：\n'
    '1. 只输出一个 JSON 对象，不要任何解释、不要 markdown 代码块。\n'
    '2. 字段：q(题干) o(长度固定的4个选项字符串数组) a(0-3整数) e(解析)\n'
    '3. 题干 15-45 字，必须自然用上给定考点里至少 2 个关键词。\n'
    '4. 四个选项长度接近，每个选项 12～26 字（严禁超过 26 字！），最长/最短 <= 1.8 倍，互不重复，每个选项必须是完整句子。\n'
    '4b. 选项不能只写一个词、一个数字或一个符号，要能独立读懂，且四个选项长度相当，不得一个很长三个很短。\n'
    '5. 只有一个正确答案；三个错项要是常见误解，不能一眼假。\n'
    '6. 题干不能出现“以上都”“下列不正确的是”这类套话开头。\n'
    '7. e 解析 42-76 字（必须落在这个区间，严禁超过 76 字），讲清为什么对以及错在哪，不重复题干。\n'
    '8. 正确答案必须放在指定下标位置。\n'
    '9. 中文与英文/数字相邻时两边各留一个空格，标点一律用中文全角。\n'
    '10. 代码标识符可用英文，但选项和题干必须通顺可读，不得半句英文半句中文硬拼。\n'
    '11. 解析中不要夹带英文原句，英文错误类名后请用中文说明。'
)



def build_prompt(point, item_id, day, ans_idx, avoid):
    lines = [
        '【考点】%s' % point['topic'],
        '【说明】%s' % point['desc'],
        '',
        '【要求】',
        '- 这道题挂在 %s 第 %d 天，属于该考点的核心理解题。' % (item_id, day),
        '- 正确答案必须放在 o 数组下标 %d。' % ans_idx,
        '- 难度对应层级 L%s（1最基础 5最难）。' % point.get('level', 1),
    ]
    if avoid:
        lines.append('- 以下题干已用过，禁止重复或近似：')
        for a in avoid[-12:]:
            lines.append('  · ' + a)
    lines.append('')
    lines.append('只输出 JSON：{"q":"...","o":["...","...","...","..."],"a":%d,"e":"..."}' % ans_idx)
    return '\n'.join(lines)


def build_exam_prompt(week, points, ans_idx, avoid):
    pts = points
    lines = []
    lines.append('以下是本周（W%d）周卷综合题，需要把本周多个考点串起来综合判断，' % week)
    lines.append('不是单点记忆题：正确选项必须体现跨考点之间的因果、依赖或先后关系。')
    lines.append('本周考点清单：')
    for p in pts:
        lines.append('  - ' + p['topic'])
    lines.append('')
    lines.append('【要求】')
    lines.append('- 正确答案必须放在 o 数组下标 %d 的位置。' % ans_idx)
    lines.append('- 题干难度 L3：需要综合两个以上考点才能作答。')
    lines.append('- 四个选项每个 14 到 32 个字；最长与最短长度比不超过 1.8 倍。')
    lines.append('- 四个选项的表述角度必须各不相同（分别从机制、时序、前提、后果切入），不允许同一句式换主体。')
    lines.append('- 解析 42 到 76 个字（严格区间），说明为什么对、为什么错，不要出现英文原句。')
    if avoid:
        lines.append('【最近已出过的题，禁止重复或换汤不换药】')
        for a in avoid[-16:]:
            lines.append('  · ' + a)
    lines.append('')
    lines.append('只输出 JSON 数组，不要解释、不要代码块标记：')
    lines.append('[{"q":"题干","o":["选项A","选项B","选项C","选项D"],"e":"解析","point_id":"考点id"}]')
    return '\n'.join(lines)

def check(q, point):
    """返回错误列表，空表示合格"""
    errs = []
    if not isinstance(q, dict):
        return ['不是 JSON 对象']
    for k in ('q', 'o', 'a', 'e'):
        if k not in q:
            errs.append('缺字段 ' + k)
    if errs:
        return errs
    stem = q['q'].strip()
    opts = q['o']
    a = q['a']
    exp = q['e'].strip()
    if not (8 <= len(stem) <= 68):
        errs.append('题干长度 %d 越界(8-68)' % len(stem))
    if len(opts) != 4:
        errs.append('选项数 %d != 4' % len(opts))
    else:
        lens = [len(str(x).strip()) for x in opts]
        if max(lens) > 28:
            errs.append('选项超 28 字: %s' % lens)
        if min(lens) < 10:
            errs.append(R_OPTTOOSHORT % (min(lens), str(opts[lens.index(min(lens))])[:20]))
        if min(lens) > 0 and max(lens) / min(lens) > 2.0:
            errs.append('选项长度比 %.2f > 2.0: %s' % (max(lens) / min(lens), lens))
        if len(set(str(x).strip() for x in opts)) != 4:
            errs.append('选项有重复')
    if not isinstance(a, int) or a < 0 or a > 3:
        errs.append('answer 非法: %r' % a)
    if not (40 <= len(exp) <= 80):
        errs.append('解析长度 %d 越界(40-80)' % len(exp))
    if _re.search(r'[A-Za-z]{3,}(?:[ ,]+[A-Za-z]{3,}){3,}', exp):
        errs.append(R_ENGLONG)
    return errs


def _merge_partial(part_path, out_path, week):
    """把 .partial 里的行去重后追加进正式 wN.jsonl，成功后把 .partial 归档为 .merged"""
    existing = set()
    if os.path.exists(out_path):
        with open(out_path, encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                key = (r.get('point_id'), (r.get('q') or '').strip()[:40])
                existing.add(key)

    rows = []
    if os.path.exists(part_path):
        with open(part_path, encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                key = (r.get('point_id'), (r.get('q') or '').strip()[:40])
                if key in existing:
                    continue
                existing.add(key)
                rows.append(r)

    if not rows:
        return 0

    with open(out_path, 'a', encoding='utf-8') as fo:
        for r in rows:
            fo.write(json.dumps(r, ensure_ascii=False) + '\n')
        fo.flush()

    arch = part_path + '.merged'
    if os.path.exists(arch):
        os.remove(arch)
    os.rename(part_path, arch)
    return len(rows)


def parse_json(text):
    t = text.strip()
    if t.startswith('```'):
        t = t.split('```')[1] if '```' in t[3:] else t[3:]
        if t.startswith('json'):
            t = t[4:]
        t = t.strip()
    s, e = t.find('{'), t.rfind('}')
    if s < 0 or e < 0:
        return None
    try:
        return json.loads(t[s:e + 1])
    except Exception:
        return None


def gen_one(env, point, item_id, day, ans_idx, avoid):
    last = ''
    for attempt in range(1, RETRY + 1):
        try:
            text = call_llm(env, build_prompt(point, item_id, day, ans_idx, avoid), SYSTEM)
        except Exception as ex:
            last = 'HTTP: %s' % ex
            s = str(ex)
            if '402' in s:
                time.sleep(30 + 2 ** attempt)
            elif '429' in s:
                time.sleep(20 + 2 ** attempt)
            elif any(x in s for x in ('502', '503', '504', 'Bad Gateway', 'Gateway', 'control unavailable')):
                # 中转站上游抖动，长退避重试（30秒起步）
                time.sleep(30 + 2 ** attempt)
            else:
                time.sleep(2 ** attempt)
            continue
        obj = parse_json(text)
        if obj is None:
            last = 'JSON 解析失败: %s' % text[:120]
            time.sleep(1)
            continue
        if obj.get('a') != ans_idx:
            # 模型放错位置：仅当选项合法时旋转
            opts = obj.get('o')
            ai = obj.get('a')
            if isinstance(opts, list) and len(opts) == 4 and isinstance(ai, int) and 0 <= ai <= 3:
                if ai != ans_idx:
                    opts = list(opts)
                    opts[ai], opts[ans_idx] = opts[ans_idx], opts[ai]
                    obj['o'] = opts
                    obj['a'] = ans_idx
        errs = check(obj, point)
        if errs:
            last = '; '.join(errs)
            time.sleep(1)
            continue
        return obj, None
    return None, last



def parse_json_array(text):
    t = (text or '').strip()
    if t.startswith('```'):
        t = t[3:]
        if t.startswith('json'):
            t = t[4:]
        if '```' in t:
            t = t.split('```')[0]
        t = t.strip()
    s, e = t.find('['), t.rfind(']')
    if s < 0 or e < 0:
        return None
    try:
        obj = json.loads(t[s:e + 1])
    except Exception:
        return None
    if not isinstance(obj, list):
        return None
    return obj


def gen_one_exam(env, week, allp, ans_idx, avoid, primary):
    last = ''
    for attempt in range(1, RETRY + 1):
        try:
            text = call_llm(env, build_exam_prompt(week, allp, ans_idx, avoid), SYSTEM)
        except Exception as ex:
            last = 'HTTP: %s' % ex
            s = str(ex)
            if '402' in s:
                time.sleep(30 + 2 ** attempt)
            elif '429' in s:
                time.sleep(20 + 2 ** attempt)
            elif any(x in s for x in ('502', '503', '504', 'Bad Gateway', 'Gateway', 'control unavailable')):
                # 中转站上游抖动，长退避重试（30秒起步）
                time.sleep(30 + 2 ** attempt)
            else:
                time.sleep(2 ** attempt)
            continue
        arr = parse_json_array(text)
        if not arr:
            last = 'JSON 解析失败: %s' % text[:120]
            time.sleep(1)
            continue
        obj = arr[0] if isinstance(arr[0], dict) else None
        if obj is None:
            last = '首元素非对象'
            time.sleep(1)
            continue
        opts = obj.get('o')
        ai = obj.get('a')
        if isinstance(opts, list) and len(opts) == 4 and isinstance(ai, int) and 0 <= ai <= 3 and ai != ans_idx:
            opts = list(opts)
            opts[ai], opts[ans_idx] = opts[ans_idx], opts[ai]
            obj['o'] = opts
            obj['a'] = ans_idx
        errs = check(obj, primary)
        if errs:
            last = '; '.join(errs)
            time.sleep(1)
            continue
        return obj, None
    return None, last


def gen_exam(env, week, items, avoid):
    allp = []
    for iid in sorted(items.keys()):
        allp.extend(items[iid]['points'])
    if not allp:
        return [], 0, 0
    n = min(EXAM_COUNT, len(allp))
    step = max(1, len(allp) // EXAM_COUNT)
    picked = []
    for k in range(n):
        idx = min(k * step, len(allp) - 1)
        picked.append(allp[idx])
    while len(picked) < EXAM_COUNT:
        picked.append(allp[len(picked) % len(allp)])

    rows = []
    fail = 0
    errs_all = []
    t0 = time.time()
    for k, p in enumerate(picked):
        ans_idx = (k + 1) % 4
        obj, err = gen_one_exam(env, week, allp, ans_idx, avoid, p)
        if obj is None:
            fail += 1
            errs_all.append('p%d: %s' % (k + 1, err))
            print('FAIL exam %d: %s' % (k + 1, err))
            continue
        row = {
            'item_id': 'w%dexam' % week,
            'day': 8,
            'q': obj.get('q', '').strip(),
            'o': [str(x).strip() for x in obj.get('o', [])],
            'a': int(obj.get('a', 0)),
            'e': obj.get('e', '').strip(),
            'point_id': obj.get('point_id') or p.get('id'),
        }
        rows.append(row)
        avoid.append(row['q'][:30])
        print('OK  exam %d/%d ans=%d' % (k + 1, EXAM_COUNT, ans_idx))
    used = time.time() - t0
    return rows, fail, used


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--week', type=int, required=True)
    ap.add_argument('--item')
    ap.add_argument('--point', default='', help="逗号分隔的 point_id 白名单，如 w4d1-p4,w4d1-p5")
    ap.add_argument('--resume', action='store_true')
    ap.add_argument('--dry', action='store_true')
    ap.add_argument('--exam', action='store_true')
    ap.add_argument('--workers', type=int, default=1)
    args = ap.parse_args()

    week = args.week
    env = load_env()
    items = load_points(week)
    if not items:
        sys.exit('W%d 无 points 数据' % week)

    os.makedirs(BANK_DIR, exist_ok=True)
    out_path = os.path.join(BANK_DIR, 'w%d.jsonl' % week)
    part_path = out_path + '.partial'

    if args.exam:
        if args.dry:
            allp = []
            for iid in sorted(items.keys()):
                for p in items[iid]['points']:
                    allp.append(p)
            step = max(1, len(allp) // EXAM_COUNT)
            picked = [allp[(i * step) % len(allp)] for i in range(EXAM_COUNT)]
            print('[dry] exam 共 %d point，step=%d' % (len(allp), step))
            for k, p in enumerate(picked):
                print('[dry] exam %d/%d point=%s ans=%d' % (k + 1, EXAM_COUNT, p.get('id'), (k + 1) % 4))
            return
        exam_avoid = []
        if os.path.exists(out_path):
            with open(out_path, encoding='utf-8') as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        r = json.loads(line)
                    except Exception:
                        continue
                    if r.get('item_id') == 'w%dexam' % week:
                        exam_avoid.append(str(r.get('q', ''))[:30])
        rows, fail, used = gen_exam(env, week, items, exam_avoid)
        with open(out_path, 'a', encoding='utf-8') as f:
            for row in rows:
                f.write(json.dumps(row, ensure_ascii=False) + '\n')
        print('=== exam rows %d, fail %d, %.1fs ===' % (len(rows), fail, used))
        for r in rows:
            print('  - %s ans=%d' % (r['q'][:28], r['a']))
        return

    done = {}
    if args.resume:
        for src in (out_path, part_path):
            if not os.path.exists(src):
                continue
            with open(src, encoding='utf-8') as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        r = json.loads(line)
                    except Exception:
                        continue
                    if not str(r.get('item_id', '')).startswith('w%dd' % week):
                        continue
                    done[r['item_id']] = done.get(r['item_id'], 0) + 1
        print('[resume] 已生成 %d 题' % sum(done.values()))

    targets = []
    for iid in sorted(items.keys()):
        day = int(iid.split('d')[1])
        pts = items[iid]['points']
        for idx, p in enumerate(pts):
            targets.append((iid, day, p, idx))

    avoid = []
    for src in (out_path, part_path):
        if not os.path.exists(src):
            continue
        with open(src, encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    avoid.append(json.loads(line)['q'][:30])
                except Exception:
                    continue

    workers = max(1, args.workers)

    want_points = set(x.strip() for x in (args.point.split(',') if args.point else []) if x.strip())

    if args.dry:
        for iid, day, p, idx in targets:
            if args.item and iid != args.item:
                continue
            if want_points and p['id'] not in want_points:
                continue
            if args.resume and done.get(iid, 0) > idx:
                continue
            print('[dry] %s %s ans=%d' % (iid, p['id'], idx % 4))
        return

    todo = []
    for iid, day, p, idx in targets:
        if args.item and iid != args.item:
            continue
        if want_points and p['id'] not in want_points:
            continue
        if args.resume and done.get(iid, 0) > idx:
            continue
        todo.append((iid, day, p, idx, idx % 4))

    ok = 0
    fail = 0
    t0 = time.time()
    avoid_lock = threading.Lock()
    ok_lock = threading.Lock()

    def _row_of(obj, iid, day, ans_idx, pid):
        return {
            'item_id': iid,
            'day': day,
            'q': obj['q'].strip(),
            'o': [str(x).strip() for x in obj['o']],
            'a': ans_idx,
            'e': obj['e'].strip(),
            'point_id': pid,
        }

    def _run_shard(shard_id, chunk):
        nonlocal ok, fail
        ppath = part_path if workers == 1 else part_path + '.%d' % shard_id
        if workers > 1 and os.path.exists(ppath):
            os.remove(ppath)
        fh = open(ppath, 'a', encoding='utf-8')
        try:
            for iid, day, p, idx, ans_idx in chunk:
                with avoid_lock:
                    snap = list(avoid)
                obj, err = gen_one(env, p, iid, day, ans_idx, snap)
                if obj is None:
                    with ok_lock:
                        fail += 1
                    print('FAIL %s %s -> %s' % (iid, p['id'], err))
                    continue
                row = _row_of(obj, iid, day, ans_idx, p['id'])
                fh.write(json.dumps(row, ensure_ascii=False) + '\n')
                fh.flush()
                with avoid_lock:
                    avoid.append(row['q'][:30])
                with ok_lock:
                    ok += 1
                    n = ok
                print('OK  %s %s (%d)' % (iid, p['id'], n))
        finally:
            fh.close()
        return ppath

    if workers == 1:
        parts = [_run_shard(0, todo)]
    else:
        buckets = [[] for _ in range(workers)]
        for i, t in enumerate(todo):
            buckets[i % workers].append(t)
        with ThreadPoolExecutor(max_workers=workers) as ex:
            futs = [ex.submit(_run_shard, sid, b) for sid, b in enumerate(buckets) if b]
            parts = [f.result() for f in as_completed(futs)]

    total_merged = 0
    if not args.dry:
        for ppath in parts:
            if os.path.exists(ppath):
                n = _merge_partial(ppath, out_path, week)
                total_merged += n
                print('[merge] %s -> %s 新增 %d 题' % (os.path.basename(ppath),
                                                      os.path.basename(out_path), n))

    print('=== 完成 item 题 %d 道，失败 %d 道，merge %d 题，用时 %.1fs ===' % (
        ok, fail, total_merged, time.time() - t0))
    if ok and not args.dry:
        print('下一步: python3 tools/gen_bank.py --week %d --exam' % week)


if __name__ == '__main__':
    main()
