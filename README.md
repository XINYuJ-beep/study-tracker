# study-tracker

纯本地离线的学习打卡 App（Flutter / Android）。无网络请求、无账号、无云同步，所有数据保存在设备本地 SQLite。

## 环境与构建

- Flutter stable，Dart 3
- Android：minSdk 26 / targetSdk 35，`namespace` 与 `applicationId` 均为 `com.xinyuj.studytracker`
- 数据层：`sqflite`，数据库文件 `study_tracker.sqlite`，`schemaVersion = 2`

常用命令：

```bash
flutter pub get
flutter gen-l10n
flutter build apk --release
flutter run
```

## 版本号（versionCode / versionName）

版本号唯一真源是 `pubspec.yaml`：

```yaml
version: 1.0.0+1
```

其中 `1.0.0` 是 versionName（给人看的），`+1` 是 versionCode（给系统看的）。

**versionCode 必须单调递增**，否则同签名的 APK 装不上去（报 `INSTALL_FAILED_VERSION_DOWNGRADE`）。

| 情况 | versionCode 是否必须加 |
| --- | --- |
| 改代码后重新打包给自己/别人覆盖安装 | 必加 |
| 只改文案/资源、重新打包但先卸载旧版 | 可不加 |
| 要发到应用市场或分发给他人长期使用 | 必加 |

### 关于 ABI 拆分

项目按 ABI 拆包，versionCode 由 `1000 * ABI_VERSION + versionCode` 合成，所以不同 ABI 的包 versionCode 不同。
如需强制统一版本号，构建时加 `-Pforce-version-code-ignoring-abi=true`。

## 签名

当前 release 构建使用 **debug 签名**（`signingConfig = signingConfigs.getByName("debug")`），目的是让任何人都能直接装上试，不需要额外配置密钥。

两条硬限制：

- 不能上架任何应用市场（debug 签名不被接受）。
- 与将来正式签名的包**互不兼容**：换签名必须卸载旧包，卸载会清空本地数据库。

转为正式签名的五步：

1. 生成 keystore：

```bash
keytool -genkey -v -keystore ~/study-tracker.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias study
```

2. 在 `android/` 下建 `key.properties`，写入 `storeFile` / `storePassword` / `keyAlias` / `keyPassword`。
3. 把 `key.properties` 和 `*.jks` 加进 `.gitignore`，密钥永不入库。
4. 在 `android/app/build.gradle.kts` 里读取 `key.properties` 建 `signingConfigs.release`。
5. 把 `buildTypes.release` 的 `signingConfig` 从 `debug` 换成 `release`。

一旦转了正式签名，**此后所有版本必须用同一个 keystore 签**，丢了就再也覆盖安装不了。

## 目录结构

```
lib/
  core/        主题、常量、数据库、Provider
  data/        仓库层与 SQL
  features/    页面与业务模块
  l10n/        国际化 arbs
android/       Android 壳工程（签名、Manifest、gradle）
```

## 数据库注意事项

- 每次改表结构必须同步导出 schema 快照，随版本一起提交。
- 开发期允许 `fallbackToDestructiveMigration`，改表即清库。
- 一旦有真实用户数据，**必须写好 Migration 并删掉 destructive 回退**，否则升级会直接清库。

## 无障碍（A11y）

- **文字对比度**：所有文字对背景 ≥4.5:1（WCAG 2.1 AA）。Gold 分两个常量：`AppColors.gold = #A67C3D` 只用于图标/装饰/图表等非文字元素（3:1 门槛）；`AppColors.goldText = #8F6329` 用于小号正文与按钮文字（对白底 5.27:1、对纸底 4.84:1）。新增文字用色必须选 `goldText`，不要图省事直接用 `gold`。
- **加载态**：首屏无文字加载页统一包 `Semantics(label: '正在加载…')`；覆盖式忙碌遮罩用 `Semantics(scopesRoute: true, namesRoute: true, label: <状态文本>)` 包整块，让 TalkBack 只读一句而不是逐节点碎读。
- **环形进度**：`_ProgressRing` 外层 `Semantics` 必须带 `container: true` 与 `excludeSemantics: true`，否则内部数字和标签会被重复朗读。
- **触达尺寸**：可点击控件最小 48×48dp。`IconButton` 一律显式写 `constraints: BoxConstraints(minWidth: 48, minHeight: 48)`，不要依赖默认值——主题 density 一变就会缩。
- **验证方式**：TalkBack / VoiceOver 实机走一遍五个页面 + 深色模式；CI 只保证语法，朗读效果必须靠真机。

## 备份策略

- 设置页提供 JSON / CSV 导出。
- 每周自动打一份 JSON 备份，只留最近 4 份，旧的自动清理，避免无限膨胀。
- 导入前先自动生成本地回滚备份，导入失败可回退到操作前状态。
- 清空数据前同样先打备份，二次确认后才执行。
