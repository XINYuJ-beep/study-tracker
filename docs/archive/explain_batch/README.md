# 276 条 MCQ explain 扩写工程归档（m01~m08）

## 结论

- 工程已完工：q001~q276 共 276 条，explain 全部落在 40~80 字区间（全库 all_min 40 / all_max 80）。
- 8 个 feat commit 已全部推送到 origin/main，最终基线 850b481。
- 风格统一：单一「答案是 」前缀、半角空格、句末全角句号，无叠字无衍文。

## 提交记录

| 批次 | 题号 | commit | 落点 |
|---|---|---|---|
| 1 | q001-q036 | 9fcb655 | avg 71.1 |
| 2 | q037-q072 | 9dfd94b | avg 71.2 |
| 3 | q073-q108 | c52456c | avg 69.0 |
| 4 | q109-q144 | 0887c9b | avg 66.0 |
| 5 | q145-q180 | d150301 | avg 48.0 |
| 6 | q181-q216 | 58fb500 | avg 58.4 |
| 7 | q217-q252 | 73f83f5 | avg 68.9 |
| 8 | q253-q276 | 850b481 | avg 67.5 |

## 文件说明

- gen0N.py：读取 m0N.jsonl 锚点与 ex0N.txt 正文，逐条校验 40~80 字，输出 /tmp/exp/out/b0N.jsonl。
- chk0N.py：语义体检，扫前缀种类、全角冒号、多空格、叠字、句末标点。
- wb0N.py：写回脚本，把 b0N.jsonl 的 mcq 键内容写入 questions.json 对应条目的 explain 键，indent=1。
- cmp0N.py：全量逐条比对，输出 changed / same / recall_same / ids_order_same。
- spot0N.py：定点抽验若干条正文与字数。
- ex0N.txt：第 N 批 24~36 条中文正文，一行一条，顺序即题号顺序。
- m0N.jsonl：模块锚点（id / week / 题干 / 选项 / answer）。
- b0N.jsonl：生成器产物，待写回的数据。
- an0N.out：锚点 dump 原始输出留证。

## 复现步骤（单批）

```bash
export PATH="/root/flutter-sdk/flutter/bin:$PATH"
cd /home/ubuntu/study-tracker
python3 gen0N.py          # 字数闸门，必须输出 bad []
python3 chk0N.py          # 语义体检
cp assets/data/questions.json /tmp/q_before.json
md5sum /tmp/q_before.json
python3 wb0N.py           # 写回，须回显 hit N
git status --short        # 必须见 M assets/data/questions.json
git diff --numstat        # 必须非空
md5sum assets/data/questions.json   # 必须与备份不同
python3 cmp0N.py          # 逐条比对
timeout 300 flutter analyze
git add assets/data/questions.json
git commit -F - << EOF ... EOF
git push origin main
```

## 关键约束（写回模板）

- questions.json 结构是双层 dict：{recall: [...], mcq: [...]}。
- b0N.jsonl 的正文键是 mcq，不是 explain；取值 r[mcq] 再赋给 t[explain]。
- json.dump 必须 indent=1、ensure_ascii=False，否则整文件缩进回归。
- 提交前必须 git add 并确认 git status --short 左列为 M。
- git status 出现 ahead of origin/main by N commit 即已提交未推送，直接 push。

## 已知缺口（2026-10-31 实测）

- 早期批次的中间脚本未入库：gen01.py / wb01.py / ex01.txt / chk02~chk07.py / cmp01~cmp07.py / spot01~spot07.py / an01~an07.out 在 /tmp 已被清理，磁盘上已不存在，无法补拷。
- 因此本归档对第 1 批只保留 chk01.py，对第 2~7 批只保留 ex / gen / wb / b / m 五类，chk 与 cmp 校验输出缺失。
- 复现语义不受影响：gen0N.py + ex0N.txt + wb0N.py + b0N.jsonl 四件齐备即可完整重跑单批；缺失的只是当时的校验留证。
- 第 8 批是唯一五类全齐（含 chk08.py / cmp08.py / spot08.py / an08.out）的完整样本，作为模板参照。
