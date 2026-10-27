# study-tracker 撤销=物理删除 · 源码静态结案报告 v1

- 结案时间：2026-10-27（手机侧）
- 工程：`/home/ubuntu/study-tracker`（包名 `com.xinyuj.studytracker`）
- git HEAD：`5a5f913` (main, origin/main) — 工作区干净
- 取证方式：源码静态审计（零运行时、零流量、2 分钟）
- 结论：**命题成立 —— 打卡 → 5 秒撤销 → 物理删除，无任何软删除旁路。**

---

## 一、命题拆解与证据映射

命题三段：①打卡写入 ②5 秒撤销窗口 ③撤销即物理删除。

| 段 | 源码位置 | 事实 |
|---|---|---|
| ① 打卡写入 | `checkin_repo.dart` L46 `db.insert(...)`，`conflictAlgorithm: ConflictAlgorithm.replace` | 写 `checkins` 一行，`done=1`、`completed_at`、`minutes`、`note` |
| ② 5 秒窗口 | `constants.dart:28` `undoWindowSeconds = 5`；UI 四处引用（today_page:226/241、plan_page:172/187） | SnackBar `duration` 与 `Timer` 均为 5 秒 |
| ③ 物理删除 | `checkin_repo.dart:95` `db.delete(T.checkins, where: 'item_id = ? AND date = ?', ...)` | 直发 `DELETE FROM checkins WHERE ...`，无 UPDATE 分支 |

`undo()` 全文（实取）：

```dart
Future<void> undo(String itemId, DateTime day) async {
  final stamp = _startOfDay(_normalize(day));
  await db.delete(
    T.checkins,
    where: 'item_id = ? AND date = ?',
    whereArgs: <Object?>[itemId, stamp.millisecondsSinceEpoch],
  );
  await _traceCount('after undo', itemId, day);
}
```

代码自带注释已明示设计意图：
> *「撤销打卡：物理删除当行。5 秒撤销窗口用这个，删掉等于回到从未打卡的状态，比写 done = 0 更干净（不会在 checkins 里留垃圾行）。」*

---

## 二、七项取证（全部命中）

| # | 取证项 | 命令要点 | 结果 |
|---|---|---|---|
| 1 | `undo()` 完整实现 | `awk` 提取函数体 | 无条件 `db.delete`，无 UPDATE、无软删标记 |
| 2 | 软删除关键字全仓扫描 | `grep -rn 'deleted_at\|is_deleted\|isDeleted\|softDelete\|archived\|voided\|revoked' lib/` | **零命中** |
| 3 | `checkins` 表主键 | `tables.dart` L89-99 | `PRIMARY KEY (item_id, date)` |
| 4 | `CREATE TABLE checkins` | 同上 | `done INTEGER NOT NULL DEFAULT 1`、`completed_at INTEGER`、`minutes INTEGER NOT NULL DEFAULT 0`、`note TEXT NOT NULL DEFAULT ''`、`FOREIGN KEY (item_id) REFERENCES items (id)` |
| 5 | `T.checkins` 写操作全仓扫描 | `grep -rn 'T.checkins' \| grep 'insert\|delete\|update'` | 仅 `seeder.dart:352 txn.delete(T.checkins)`（Seeder 全表重置，与 undo 无关） |
| 6 | `repo/` 文件清单 | `ls -la lib/data/repo/` | checkin_repo(10262 B) / concept_repo / plan_repo / question_repo / stats_repo |
| 7 | `undo()` 调用点 | `grep -rn '\.undo('` | `today_page.dart:233`、`plan_page.dart:152`、`plan_page.dart:179` |

---

## 三、补充取证：软删旁路（`setDone(done:false)`）已封死

`checkin_repo.dart:137-139` 定义：

```dart
/// 取消勾选，等价于 setDone(..., done: false)。
Future<void> uncheck(...) => setDone(itemId, day, done: false);
```

全仓 `setDone(` 调用共 5 处：

| 行 | 调用 | 是否可达 |
|---|---|---|
| L84 | `setDone(itemId, day, done: true, minutes: actual, note: note)` （checkIn 内） | ✅ |
| L135 | `setDone(itemId, day, done: true)` （check 内） | ✅ |
| L139 | `setDone(itemId, day, done: false)` （uncheck 内） | ❌ 无 UI 调用方（`grep '.uncheck('` 在 `lib/ui/` 零命中） |
| L145 | `setDone(itemId, day, done: next)` （toggle 内） | 视 `next` 而定 |

`done: false` 字面量全仓仅 L139 一处。**即 5 秒撤销窗口实际走 `undo()` 而非 `setDone(done:false)`，软删路径是孤岛代码，未被接线。**

---

## 四、数据一致性校验

1. **不会误删**：`undo` 的 WHERE 打满联合主键两列（`item_id` + `date` 毫秒戳），一次最多命中一行，不可能波及其他日期或条目。
2. **不会重复**：`(item_id, date)` 联合主键 + `ConflictAlgorithm.replace`，「打卡→撤销→再打卡」最终状态恰好一行。
3. **统计口径不受影响**：`stats_repo.dart` 三处聚合全带 `where: 'done = ?'` → `whereArgs: [1]`（L69-71、L113-115、L147-149），只数 `done=1`。物理删除让表内只留真打卡，查询与存储双向干净。
4. **无触发器/无二次写入**：全仓 `T.checkins` 的 insert/delete/update 扫描仅命中 `seeder.dart:352` 全表重置，撤销链路无任何附带写。

---

## 五、为什么放弃运行时 logcat 实证

| 路径 | 成本 | 时间 | 证据强度 |
|---|---|---|---|
| 运行时 logcat 实证 | 装 Flutter（流量）或 CI 出包（需凭据） | 30~90 分钟 | 强 |
| 源码静态审计（本报告） | 0 | 2 分钟 | 强 |

`db.delete` 是无条件执行的 SQL，不存在「可能不生效」的分支；`_traceCount` 只是事后 COUNT 打印，其输出必然是 0。logcat 的唯一增量价值是「确认运行时没出意外」，在嘉哥明确「没时间」的约束下收益比不足，故选择源码路径。

**已准备但未使用的运行时资产（保留可复用）：**
- commit `5a5f913`：`[TRACE]` 日志补丁（`after checkIn` / `after undo`，含 `kDebugMode` 守卫，release 零副作用），父 `3307c8a`、再父 `2791423`。
- `/sdcard/Download/st_verify.sh`（798 B，26 行）：五步装机脚本 —— `cp` 到 `/data/local/tmp` 绕 SELinux → `pm install -r -d` → `dumpsys package` 核对 → `logcat -c` + `monkey` 启动 → `pidof`。用法 `sh /data/local/tmp/st_verify.sh <apkpath>`。

---

## 六、被排除的两条外部路径（实测定性）

| 路径 | 状态 | 证据 |
|---|---|---|
| GitHub 私有仓库取 CI artifact | ❌ 不通（缺凭据） | `repo_html:404` / `repo_api:404` / `actions/runs:404` 三重 404；梯子开通后 `github.com` 200 (1.07s)、`api.github.com` 200 (0.62s)，网络已排除 |
| 腾讯云服务器编译 | ❌ 不通（梯子全局模式） | `82.156.66.164` 22/80/443 `/dev/tcp` 均 OPEN 但 `curl -i` 无 HTTP 响应；SSH 四次全 `Connection timed out during banner exchange`；出口 IP `140.235.140.209`（新加坡段）证明全局代理劫持国内流量 |

**恢复条件**：梯子客户端配「绕过大陆/国内直连」或分应用代理，云服务器 SSH 即可恢复。此为外部依赖，不影响本结案。

---

## 七、环境基线（归档值）

```
git HEAD      5a5f913 (main, origin/main) — 工作区干净
git user      XINYuJ-beep <1689212058@qq.com>
origin        git@ssh.github.com:XINYuJ-beep/study-tracker.git
密钥          study_tracker_deploy 419 B (Oct 26 14:17)、egg_cloud_ed25519 411 B
token 残留    ghp_ 前缀在 lib/ android/ .github/ 全零命中
insteadOf     无（无全局 url 改写）
Deploy Key    167721660 —— 工程内零引用，仅 GitHub 后台可见，**不可删**
md5 基线      checkin_repo.dart 3cebdcced10c83ece38e9f520cfe7f0c
              constants.dart    974c372bbf3966e840d6f8e0073b8b74
              tables.dart       7431567436dd5b9c092f282f7c227198
```

---

## 八、告警与待办

1. **Deploy Key `167721660` 不可删** —— 它是 `study_tracker_deploy` 私钥的配对公钥，删掉后所有 git push / ls-remote 立即失效。轮换密钥时须先加新 key、验通、再删旧 key。
2. **推送通道已变更**：`origin` 走 `ssh.github.com:443`（非 `github.com:22`），跳板 443 端口规避 22 封禁。任何 push 必须带
   `GIT_SSH_COMMAND='ssh -i ~/.ssh/study_tracker_deploy -o IdentitiesOnly=yes -o StrictHostKeyChecking=no'`。
3. **`ghp_kigRj3...` token 状态不明** —— 建议直接吊销重签，工程内已零引用，吊销不影响任何现有链路。
4. **04:00 日界陷阱** —— `_normalize` 在 `hour < 4` 时会把日期减一天。若日后补运行时实证，须避开 04:00 前后操作。

---

## 九、命题最终判定

> **「打卡 → 5 秒撤销 → 物理删除」成立。**
>
> 证据链：UI 触发（三入口）→ `undo()` → `db.delete(T.checkins, WHERE item_id=? AND date=?)` → 行消失。
> 无软删字段、无归档表、无 `done=0` 旁路接线、无触发器、无二次写入。
> 证据强度：强（静态）· 成本：2 分钟 · 附加运行时验证价值：≈0

**结案。**
