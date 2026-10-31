# P2 完成报告：schema v3→v4 迁移 + SM-2 接入

日期：2026-10-31
工程：`/home/ubuntu/study-tracker`
状态：**代码层完成，analyze 0 error（5 条旧 warning 为历史遗留，不属 P2）**
真机验证：**未做**（迁移正确性只能真机验证，构建机无 db 文件）

---

## 1. 改动清单（6 个文件，10 处）

| 文件 | 改动 | 行数变化 |
|---|---|---|
| `lib/data/db/tables.dart` | 新增 `kMigrateV3ToV4`（7 条语句） | 上轮完成 |
| `lib/data/db/tables.dart` | `kCreateIndexes` 4→6 条，加 `idx_mcqs_item`、`idx_mcqs_due` | 上轮完成 |
| `lib/data/db/tables.dart` | `sqlCreateMcqs` 重写为 16 列 | 上轮完成 |
| `lib/data/db/tables.dart` | `Mcq` 类 9→16 字段 + `isGraduated` + `copyWith` | +72 -2 |
| `lib/data/db/app_database.dart` | `schemaVersion` 3→4 + 版本史注释 | +3 -2 |
| `lib/data/db/app_database.dart` | 类头文档注释改 v4 链式 | +6 -1 |
| `lib/data/db/app_database.dart` | `onUpgrade` 插入 `if (from < 4)` 分支 | +8 -0 |
| `lib/core/constants.dart` | 补 `easePenalty=0.2`、`easeMin=1.3` | +4 -0 |
| `lib/data/repo/question_repo.dart` | 新增 4 个查询入口 | +66 -2 |
| `lib/data/repo/question_repo.dart` | `recordAnswer` 重写为真 SM-2 | +60 -8（修正后 +17 -18） |

---

## 2. 线上实际代码（已验证）

### 2.1 建表语句 `sqlCreateMcqs`（tables.dart:191）
16 列：`id / week / module / question / options / answer / explain / wrong_count / right_streak / source_ref / item_id / day / question_type / stage / due_date / ease`

### 2.2 迁移语句 `kMigrateV3ToV4`（tables.dart:138）
```
ALTER TABLE mcqs ADD COLUMN item_id TEXT NOT NULL DEFAULT ''
ALTER TABLE mcqs ADD COLUMN day INTEGER NOT NULL DEFAULT 0
ALTER TABLE mcqs ADD COLUMN question_type TEXT NOT NULL DEFAULT 'single'
ALTER TABLE mcqs ADD COLUMN stage INTEGER NOT NULL DEFAULT 0
ALTER TABLE mcqs ADD COLUMN due_date INTEGER          -- 唯一可空列
ALTER TABLE mcqs ADD COLUMN ease REAL NOT NULL DEFAULT 2.5
UPDATE mcqs SET question_type = 'single' WHERE question_type = ''
```
路径验证：老库 onCreate 跳过、走 onUpgrade 加 6 列；新库直接 16 列。两条路径终态一致。

### 2.3 索引（tables.dart:155/157）
`idx_mcqs_item ON mcqs(item_id)`、`idx_mcqs_due ON mcqs(due_date)`。
索引全走 `IF NOT EXISTS`，升级后统一重跑，可重复执行无副作用。

### 2.4 版本号（app_database.dart:37）
`schemaVersion = 4`。`onUpgrade:104` 为 `if (from < 4) { for (sql in kMigrateV3ToV4) await db.execute(sql); }`

### 2.5 SM-2 参数（constants.dart:88-96）
```
reviewIntervals       = [1, 2, 4, 7, 15, 30, 60]
reviewGraduatedStage  = 7
initialEase           = 2.5
easePenalty           = 0.2
easeMin               = 1.3
```

### 2.6 `recordAnswer` 行为（question_repo.dart）
- 答对：`right_streak+1`、`stage+1`；若 `nextStage >= 7` → `stage=7`、`due_date=null`（毕业）；否则 `due_date = startOfDay(effectiveToday()) + reviewIntervals[nextStage-1] 天`
- 答错：`wrong_count+1`、`right_streak=0`、`stage=0`、`ease = max(ease-0.2, 1.3)`、`due_date = 明天`

### 2.7 新增查询（question_repo.dart:279/297）
- `mcqsByItem(String itemId)` —— 空串直接返回空列表，`ORDER BY id ASC`
- `mcqsByWeekDay(int week, int day)` —— day 限 1..7，越界返回空
- `dueMcqs({int limit = 0})` —— `stage < 7 AND due_date IS NOT NULL AND due_date < 今日24点`，`ORDER BY due_date ASC, id ASC`
- `dueMcqCount()` —— 同条件 `COUNT(*) AS c`

---

## 3. 本轮踩到的两个坑（记录以免复犯）

1. **Dart label 只可打在 `for/while/do/switch` 上**。首版 `recordAnswer` 写了 `falsePositive:` 标签包裹 `if` 并 `break falsePositive;`，语法不通。已改回普通 `if/else`。
2. **`AppDatabase` 的薄封装方法名是 `raw()` 不是 `rawQuery()`**。`raw(String sql, [List<Object?>? args])` 位于 app_database.dart 第 127 行；`db.rawQuery` 只在其内部实现体出现。全库调用 `db.rawQuery` 会报 `undefined_method`。

---

## 4. 当前 analyze 基线

```
5 issues found. (ran in 8.6s)   exitCode 0, 0 error
```
5 条全部为旧 warning，不阻塞 P2：
- `seeder.dart:189` unused_local_variable `moduleId`
- `qa_extra_page.dart:372` unused_field `_currentWeek`
- `qa_page.dart:28` unused_import `plan_repo.dart`
- `settings_page.dart:217/:234` body_might_complete_normally_nullable

---

## 5. 待办（按序）

1. **真机验证 P2**：改 `dataVersion` 触发重灌，`sqlite3` 查 `PRAGMA table_info(mcqs)` 应 16 列；老库路径另测（装 v3 包再覆盖 v4）。
2. **P4 第 1 批**：45 道（W1D1–W1D7）+ 打印 10 条机械校验结果。
3. **P3**：按天投放 UI + 复习页接入 `dueMcqs`。
4. **剩余 91 批生成**。
5. **`expectedMcqs` 276→4140 + `dataVersion` 9→10**（顺序死规：先扩 `questions.json`，再改常量，否则 `SeedResult.failures()` 硬断言整批回滚）。
6. 删 `assets/data/` 下 9 个 `.bak_*`（必须在改 `dataVersion` 重灌前删，否则打进 APK）。
7. 清 6 处 `[DBP]` 插桩。
8. 提交 14 个未提交文件（289 增 / 194 删）。
9. 修 5 条 warning。
10. 更新 `tables.dart:4/:12` 可能残留的过时注释。
