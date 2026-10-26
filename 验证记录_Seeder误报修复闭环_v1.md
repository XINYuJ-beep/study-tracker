# Seeder 误报 bug 修复闭环验证记录 v1

日期：2026-10-26
提交：ce40bfe561d31c7b4c660baa081aa8cc7f20e60d
上一提交：da936a51169a73a4946574b63f5f10c654b29685
CI Run：40255955907 -> completed success

## 一、推送通道问题（已解决）

### 根因
DNS 把 github.com 解析到 20.205.243.166，该 IP 在 Ubuntu(proot) 侧 TCP 建连耗时约 15 秒，
首包等待超时，git 被 timeout 杀掉。而 curl 走 api.github.com(20.205.243.168) 可达，
造成「curl 200 但 git 卡死」的错觉，不是凭据 / TLS / 代理问题。

### 关键环境认知（务必牢记）
proot(Ubuntu) 的 127.0.0.1 不等于 Android 宿主的 127.0.0.1。
证据：Android 侧 netstat 显示 7892 有大量 ESTABLISHED 连接，
但 Ubuntu 侧 curl -x 127.0.0.1:7892 返回 http_code=000；
Android 侧 /system/bin/curl -x 127.0.0.1:7892 同样返回 000（0.0035s）。
结论：Clash 端口虽在监听，但代理连接不被接受，两条路都走不通。

### 解决方案（可用）
    git -c http.curloptResolve=github.com:443:20.27.177.113 <push|ls-remote>

实测 IP 连通性（Ubuntu 侧 /dev/tcp 探活）：

| IP | 结果 | 耗时 |
|---|---|---|
| 20.205.243.166 | FAIL | 6042ms（DNS 默认，必须避开） |
| 20.27.177.113 | OK | 131ms（首选） |
| 20.200.245.247 | OK | 171ms |
| 4.237.22.38 | OK | 280ms |
| 140.82.114.3 | OK | 325ms |
| 140.82.113.3 | OK | 376ms |
| 140.82.112.3 | OK | 473ms |
| 140.82.121.3 | OK | 551ms |

### 配置清理（已做）
/root/.gitconfig（全局层）中的 [http] proxy / [https] proxy 两行已删除，
备份在 /root/.gitconfig.bak.<epoch>。
git config --unset / --unset-all 在本仓库未生效，改配置文件是可靠手段。

## 二、CI 双产物改造（ce40bfe 生效）

workflow 新增：
- Build profile APK (log-visible)：flutter build apk --profile
- Stash profile APK：cp 到 /tmp/app-profile.apk
- upload artifact study-tracker-apk-profile（保留 30 天）

原有 study-tracker-apk（release）保留。

本次产物：
- study-tracker-apk：23818688 B（release）
- study-tracker-apk-profile：33044458 B（profile）
- 解压后 app-profile.apk 69088602 B，md5 = 7f20907c5f7a5ce9b90e1f4714343937

## 三、真机验证结果（通过）

设备：三星 Z Fold3
包名：com.xinyuj.studytracker（注意 studytracker 无下划线，旧记录 com.xinyuj.study_tracker 是错的）
versionName：0.1.0
安装时间：2026-10-26 09:57:25

### 第 1 次冷启动
    [DB] onCreate done: version=2 tables=10/10
    无 [SEED] failed

说明：全新安装，建库成功。

### 第 2 次冷启动
    无 [DB] onCreate（库已存在，走跳过分支）
    无 [SEED] failed    <-- 核心验证点，误报 bug 已修复

### 第 3 次冷启动
    [SEED] failed 计数 = 0

### 数据侧复核（两次冷启动后导出 DB）

导出方式：

    run-as com.xinyuj.studytracker base64 app_flutter/study_tracker.sqlite > /data/local/tmp/st.b64
    # 拷到 /sdcard 后转 Ubuntu 侧 base64 -d 还原

注意两个坑：
1. run-as 身份不能写 /data/local/tmp（Permission denied）
2. run-as 直接重定向到 /sdcard 会得到 0 字节（SELinux 拦截）
   必须 base64 中转

表行数核对：

| 表 | 实际 | 期望 | 结论 |
|---|---|---|---|
| items | 644 | 644 | OK |
| weeks | 92 | 92 | OK |
| modules | 8 | 8 | OK |
| cards | 736 | 736 | OK |
| mcqs | 276 | 276 | OK |
| concepts | 129 | 129 | OK |
| stages | 8 | 8 | OK |
| streams | 6 | 6 | OK |
| checkins | 0 | 0 | OK（尚未打卡） |

app_settings：('data_version', '2')

数据完整、未重复插入、未被破坏。

## 四、环境踩坑补充

1. profile 包是 DEBUGGABLE，run-as 可用。上一轮「run-as 不可用」的结论是 release 包导致的，条件已变。
2. aapt / aapt2 在 Android shell 侧不可用，包名靠 pm list packages -3 推断。
3. com.ai.assistance.operit（聊天宿主）和 com.android.chrome 会抢前台，截图验证不可靠，
   优先用数据侧 + logcat 验证。
4. Dart VM service 的 SocketException（127.0.0.1 bind, errno=1）是 profile 包在 shell 下的环境噪音，
   与 App 逻辑无关，忽略。
5. logcat -d -s flutter:* 比 --pid 过滤更稳（App 重启后 pid 会变）。

## 五、结论

Seeder 误报 bug 已闭环：

- 代码提交 ce40bfe 已推送成功，CI Run 40255955907 成功
- profile 包真机三次冷启动全部无 [SEED] failed
- 数据库 644 / 92 / 8 / 736 / 276 / 129 / 8 / 6 全对，data_version = 2
- 第 2 轮（今日页 + 打卡 + 复习队列）收尾验证完成
