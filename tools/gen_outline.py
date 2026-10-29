# -*- coding: utf-8 -*-
import json, sys, re, os
from collections import Counter
# ---
BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLAN = os.path.join(BASE, 'assets', 'data', 'plan.json')
OUTDIR = os.path.join(BASE, 'docs', 'da-gang')
KWFILE = '/tmp/kw.txt'
C_MARK = ('周日', '周复习')
SUN = '周日'
# C 形态（周复习）代码题档位配额：C1 纯概念 / C2 手写代码 / C3 代码阅读
C_TIERS = ('C1','C1','C1','C2','C2','C3')
# ---
def load_kp():
    raw = open(KWFILE, encoding='utf-8').read()
    return tuple(x for x in raw.split('---') if x)
KP = load_kp()
# ---
# 教材锚点：watch 段出现集/章/讲/周或数字区间 -> A 加分
WATCH_MARK = ('集','章','讲','周','第')
# 产物词：output 段是这些东西 -> B（动手产出，不考字面知识点）
OUT_PROD = ('代码','项目','APK','apk','服务','环境','流水线','作品','提交','部署','脚本','接口','页面','仓库')
# 沉淀词：output 段是这些东西 -> A（知识沉淀，可考字面）
OUT_NOTE = ('笔记','卡片','题解','报告','记录','总结','复盘','整理','提纲','清单')

def _is_watch_anchor(w):
    if not w:
        return False
    for m in WATCH_MARK:
        if m in w:
            return True
    if re.search(r'\d+\s*[-~至]\s*\d+', w):
        return True
    return False

def classify(it):
    day = it.get('day', '')
    w = it.get('watch', '') or ''
    pr = it.get('practice', '') or ''
    out = it.get('output', '') or ''
    if day in C_MARK or day == SUN:
        return 'C'

    body = w + '|' + pr + '|' + out
    hits = [k for k in KP if k in body]
    ascii_cnt = sum(1 for ch in pr if ch.isascii() and ch.isalnum())
    short_practice = len(pr) < 6

    # 规则三：output 分流
    is_prod = any(x in out for x in OUT_PROD)
    is_note = any(x in out for x in OUT_NOTE)
    # 规则一：watch 是教材锚点
    watch_anchor = _is_watch_anchor(w)

    score = 0
    if len(hits) >= 2:
        score += 2
    elif len(hits) == 1:
        score += 1
    if watch_anchor:
        score += 2
    if is_note:
        score += 1
    if is_prod:
        score -= 1
    if len(pr) >= 12:
        score += 1
    if ascii_cnt >= 6:
        score += 1

    a = False
    if score >= 3:
        a = True
    elif score == 2 and (watch_anchor or len(hits) >= 1):
        a = True

    # 规则二：practice 短于 6 字，禁止判 A，除非 watch 是明确教材锚点且 output 是沉淀类
    if short_practice and not (watch_anchor and (is_note or len(hits) >= 1)):
        a = False
    if is_prod and not watch_anchor and len(hits) == 0:
        a = False

    return 'A' if a else 'B'

# ---
def main():
    data = json.load(open(PLAN, encoding='utf-8'))
    mods = data['modules']
    idx = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    sel = mods if idx == 0 else [mods[idx - 1]]
    os.makedirs(OUTDIR, exist_ok=True)
    gstat = Counter()
    for m in sel:
        mid = str(m['id']).zfill(2) if isinstance(m['id'], int) else str(m['id'])
        lines = []
        cnt = Counter()
        items = [it for wk in m['weeks'] for it in wk['items']]
        lines.append('# ' + str(m['title']))
        lines.append('')
        lines.append('- ' + str(m.get('sub', '')))
        lines.append('- 目标: ' + str(m.get('goal', '')))
        lines.append('- 验收: ' + str(m.get('accept', '')))
        lines.append('- 周数: %d | item: %d | 题目: %d' % (len(m['weeks']), len(items), len(items) * 6))
        lines.append('')
        for wk in m['weeks']:
            lines.append('## W%d %s' % (wk['week'], wk.get('title', '')))
            lines.append('')
            lines.append('目标: ' + str(wk.get('goal', '')))
            lines.append('')
            lines.append('复习: ' + str(wk.get('review', '')))
            lines.append('')
            for it in wk['items']:
                g = classify(it)
                cnt[g] += 1
                gstat[g] += 1
                lines.append('### %s | %s | 形态 %s' % (it['id'], it.get('day', ''), g))
                lines.append('')
                lines.append('- 看: ' + str(it.get('watch', '')))
                lines.append('- 练: ' + str(it.get('practice', '')))
                lines.append('- 出: ' + str(it.get('output', '')))
                lines.append('- 时长: %s 分' % it.get('minutes', ''))
                lines.append('')
                lines.append('| 编号 | 题型 | 难度 | 档位 | 考点方向 |')
                lines.append('| --- | --- | --- | --- | --- |')
                qt = ('single','single','single','single','boolean','reverse')
                lv = ('D1','D2','D3','D4','D5','D6')
                for qi in range(6):
                    tier = C_TIERS[qi] if g == 'C' else '-'
                    lines.append('| Q%d | %s | %s | %s | 待填 |' % (qi+1, qt[qi], lv[qi], tier))
                lines.append('')
        tot = sum(cnt.values()) or 1
        lines.append('## 形态统计')
        lines.append('')
        lines.append('| 形态 | 数量 | 占比 |')
        lines.append('| --- | --- | --- |')
        for g in ('A', 'B', 'C'):
            lines.append('| %s | %d | %.1f%% |' % (g, cnt[g], cnt[g] * 100.0 / tot))
        lines.append('')
        p = os.path.join(OUTDIR, 'mod-%s.md' % mid)
        open(p, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
        print('WROTE %s rows=%d items=%d A/B/C=%d/%d/%d' % (p, len(lines), len(items), cnt['A'], cnt['B'], cnt['C']))
    t = sum(gstat.values()) or 1
    print('TOTAL items=%d A=%d(%.1f%%) B=%d(%.1f%%) C=%d(%.1f%%)' % (t, gstat['A'], gstat['A']*100.0/t, gstat['B'], gstat['B']*100.0/t, gstat['C'], gstat['C']*100.0/t))
# ---
if __name__ == '__main__':
    main()
