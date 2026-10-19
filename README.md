# OpenList Client

OpenList 的 Windows / Android 原生客户端。单代码库 Flutter 3.x，视觉与交互严格按 `OpenList-Client-Design.html` v1.3 的 W1–W9 / A1–A8 画板实现，不使用 WebView 包裹设计稿，也不引入任何外部图片或字体资源。

| 项目 | 说明 |
| --- | --- |
| 框架 | Flutter 3.x stable · Material 3（仅作底座，视觉全部来自设计令牌） |
| 状态 / 路由 | Riverpod · go_router |
| 网络 | dio + 自研 `OpenListApi` |
| 播放 | media_kit（libmpv）· Range 直读 |
| 安全存储 | flutter_secure_storage（Windows Credential Manager / Android Keystore） |
| 目标平台 | Windows 10/11 x64 · Android 8.0+（minSdk 26） |
| 管理后台 | 决策 A：只读（存储健康 / 容量），写操作跳浏览器 |

## 进度

| 阶段 | 内容 | 状态 |
| --- | --- | --- |
| P1 | 脚手架、设计令牌、路由、API 客户端、安全存储 | ✅ 完成 |
| P2 | 登录、多服务器、文件浏览 / 搜索、四态 | ✅ 完成 |
| P3 | 传输（续传 / 限速 / 队列）、media_kit 播放 | ✅ 完成 |
| P4 | 托盘 / 单实例、Android 出包与 Release 发布 | ✅ 完成（Windows 安装包待 Windows 机器执行打包脚本） |

构建状态：CNB `main` 分支流水线通过，`static-check` + `build-android` 全绿；
tag `v1.0.0` 触发发布流水线，APK 作为 Release 附件上传。

## 发布（Release）

| 项 | 值 |
| --- | --- |
| 版本 | [`v1.0.0`](https://cnb.cool/haoxuanhaoxuan/OpenList-Client/-/releases/tag/v1.0.0) |
| 产物 | `OpenList-Client-1.0.0-android-arm64.apk`（65,464,152 字节 / 62.4 MiB） |
| SHA-256 | `8bbfbc3b2366f676404a06bfffa478b09e73e36f1e8c03a18fb9ed967914f50b` |
| 下载 | <https://cnb.cool/haoxuanhaoxuan/OpenList-Client/-/releases/download/v1.0.0/OpenList-Client-1.0.0-android-arm64.apk> |
| 说明 | Release APK 为 debug 签名，可直接安装验收；上架前请替换 keystore |

下载后可校验一致性（与构建日志里的 `sha256sum` 输出比对）：

```bash
curl -L -o app.apk https://cnb.cool/haoxuanhaoxuan/OpenList-Client/-/releases/download/v1.0.0/OpenList-Client-1.0.0-android-arm64.apk
sha256sum app.apk
# 8bbfbc3b2366f676404a06bfffa478b09e73e36f1e8c03a18fb9ed967914f50b
```

发布流程（全自动）：

```bash
# 1) 提交并推送 main（触发构建校验）
git push origin main
# 2) 打好 tag 并推送（触发 release 流水线：构建 → 上传附件）
git tag -a v1.0.0 -m "OpenList Client v1.0.0"
git push origin v1.0.0
```

`tool/ci_publish_release.sh` 会按 tag 反查 Release、申请上传地址、PUT 上传、确认附件；
Release 需提前在 CNB 控制台创建（或调用 OpenAPI），脚本最多重试 12 次 × 15s 等待其就绪。

## 画板对照

| 画板 | 实现文件 | 说明 |
| --- | --- | --- |
| W1 连接服务器 | `lib/features/auth/login_page.dart` | 左侧艺术面板 + 右侧表单，地址探测、密码 / Token / 两步验证、最近服务器 |
| W2 文件管理 | `lib/features/files/files_page.dart` | 三栏：挂载点 / 列表 / 详情；面包屑、多选、排序、筛选、拖拽上传、右键菜单 |
| W3 传输中心 | `lib/features/transfers/transfers_page.dart` | 速度卡 + 曲线、四宫格、任务队列、限速与并发 |
| W4 跨盘搜索 | `lib/features/search/search_page.dart` | 命令面板（Ctrl K）、300ms 防抖、范围 0/1、键盘上下选择 |
| W5 播放器 | `lib/features/media/player_page.dart` | 强制深色、Range seek、倍速、音量、同目录播放列表、字幕自动匹配 |
| W6 设置 | `lib/features/settings/settings_page.dart` | 账户、存储只读、传输、播放、外观、通知、隐私、关于 |
| W7 深色文件页 | 同一套布局 + `OlPalette.dark` | 跟随系统 / 手动切换，播放器始终深色 |
| W8 服务器管理 | `lib/features/servers/servers_page.dart` + `server_form.dart` | 左侧列表点选、右侧同屏编辑、搜索与状态筛选、导入导出 |
| W9 托盘 | `lib/platform/windows/tray.dart` | 四态图标（运行时绘制 PNG）、左键打开、右键菜单、关闭收进托盘、单实例 |
| A1 登录 | 同上登录页（窄屏分支） | 深色沉浸、玻璃表单、最近服务器 |
| A2 文件 | `files_page.dart` 移动分支 | 存储卡横滑、类型 chips、长按操作面板、下拉刷新、FAB |
| A3 传输 | `transfers_page.dart` 移动分支 | 速率卡 + 分组 chips + 任务卡 |
| A4 搜索 | `search_page.dart` 移动分支 | 搜索条、范围切换、分组结果 |
| A5 播放 | `player_page.dart` | 全屏媒体 + 自定义控制条 |
| A6 我的 | `settings_page.dart` 移动分支 | 头像 / 实例 / 统计 + 设置列表 |
| A7 文件操作面板 | `files_page.dart` → `_showMobileSheet` | 播放 / 下载 / 分享 / 收藏 + 重命名 / 移动 / 复制 / 删除 |
| A8 服务器 | `servers_page.dart` 移动分支 + `server_edit_page.dart` | 当前实例卡、其余实例卡、切换行为、导入导出 |

## 已实现

- **登录**：地址探测（`/api/public/settings`，带版本与站点名）、密码登录、API Token、两步验证码、内联错误（不弹窗）、HTTP 仅内网放行。
- **多服务器**：数量不限，列表本地持久化；凭据逐实例写入系统安全存储；独立下载目录 / 独立媒体缓存 / 记住浏览位置；切换时可按设置暂停旧任务；删除仅移除本地配置，当前实例被删后自动切换。
- **文件浏览**：分页（100/页，滚动续载）、面包屑、刷新、按名称/大小/修改时间排序、类型筛选、列表/网格、全选与 Shift 之外的 Ctrl 多选、批量下载/删除/移动/复制、新建文件夹、重命名、分享（有效期 + 提取码）、离线下载。
- **四态**：空目录插画 + 主按钮；骨架屏延迟 400ms 出现；连接失败横幅 + 重试 + 诊断；离线时展示本地缓存的目录并可读。
- **搜索**：`/api/fs/search`，当前目录 / 全部挂载两种 scope，键盘 ↑↓ + Enter。
- **传输**：下载（Range 续传、暂停/继续/重试、重启后从已写入字节继续）、上传（`PUT /api/fs/put` + `File-Path`）、离线任务查询、实时速率、并发与下载限速、任务持久化。
- **播放**：media_kit 流式播放、进度记忆、倍速、音量、同目录播放列表、同目录字幕自动挂载。
- **托盘**：Windows 四态图标由 Canvas 运行时绘制并写入临时目录（不依赖外部图片）；左键唤起、右键菜单（服务器切换 / 暂停全部 / 传输中心 / 退出）；关闭窗口收进托盘；UDP 单实例。
- **桌面能力**：自绘标题栏（拖动 / 最小化 / 最大化 / 关闭）、Ctrl K / Ctrl U / Ctrl Shift N / F2 / Delete / F5 / Space 快捷键、拖拽上传、右键菜单、最小窗口 1024×680。

## 首版边界

不做：管理写操作（`storage create/update/delete`、`user/*`、`index/*`，一律跳浏览器）、iOS / macOS / Linux、自建账号体系、云同步设置、WebView 外壳。
未纳入本次交付：Android 画中画与前台服务通知（`PiP` / 通知栏进度）、压缩下载 ZIP、多窗口、内置更新器。以上均在画板中标注为后续增项。

## 目录

```
lib/
  app/            # 根组件、路由、窗口外框、Provider 图
  core/           # api / models / storage / theme / widgets
  features/       # auth servers files transfers search media settings
  platform/       # windows/tray.dart（托盘）、windows/single_instance.dart
android/          # 完整可构建的 Android 工程（minSdk 26 / compileSdk 35）
assets/tray/      # 托盘四态图标（运行时资源白名单内）
design/           # 设计稿原件（只作视觉依据，不参与构建，见下节）
tool/             # Windows 平台引导与打包脚本
installer/        # Inno Setup 安装版脚本
.cnb.yml          # 云端构建流水线
```

## 设计稿隔离（design/）

单文件设计稿已随仓库提交：`design/OpenList-Client-Design.html`（v1.3，W1–W9 / A1–A8）。
它只作为视觉与交互依据，**构建、分析、打包全流程都不会读取或处理它**。

### 为什么不能只靠 .gitignore

`.gitignore` 只过滤**未跟踪**文件，它既不决定构建行为，也无法把已入库文件“排除出构建”。
所以这里用「强制入库 + 忽略规则 + 三层构建隔离」组合：

1. **强制入库一次**：`git add -f design/OpenList-Client-Design.html`。
   之后该文件仍被 Git 正常跟踪（可 diff / 检出 / 归档），`.gitignore` 不会让它从仓库消失。
2. **忽略规则**：挡住 `design/` 下后续产生的导出图、截图、临时副本，避免被顺手提交；
   同时让任何按目录扫描仓库的脚本把 `design/` 视为非源码目录。
3. **构建隔离**：Flutter 只编译 `lib/`、只打包 `pubspec.yaml` 中 `assets:` 白名单里的资源；
   分析器 exclude `design/**`；CI 再对产物做反查断言。

### .gitignore 中的具体配置

```gitignore
# 设计稿（随仓库分发，但永不参与构建 / 打包）
# 语义：.gitignore 只作用于未跟踪文件；本文件已用 git add -f 强制入库。
design/
design/**/*.html
design/**/*.htm

# 生成物与平台临时文件（与设计稿无关，节选）
build/
.dart_tool/
android/.gradle/
windows/flutter/ephemeral/
```

配合的两处声明：

```yaml
# analysis_options.yaml —— 分析器不读设计稿
analyzer:
  exclude:
    - "**/*.g.dart"
    - design/**
```

```yaml
# pubspec.yaml —— 资源是白名单，只有托盘图标会进包
flutter:
  uses-material-design: false
  assets:
    - assets/tray/
```

`.cnb.yml` 的 build 阶段还会执行「设计稿隔离校验」：在 `build/flutter_assets`、
`AssetManifest.json` 与最终 APK 里反查 `design` / `OpenList-Client-Design`，命中即让流水线失败。

### 如何验证构建确实忽略了设计稿

本地（验证 git 侧规则）：

```bash
# 1) 规则命中：--no-index 表示“忽略索引状态，只查 ignore 规则”
git check-ignore -v --no-index design/OpenList-Client-Design.html
# 预期输出：.gitignore:43:design/	design/OpenList-Client-Design.html

# 2) 仍被跟踪：证明它是入库文件，不是被 gitignore 挡在仓库外
git ls-files design/
# 预期输出：design/OpenList-Client-Design.html

# 3) 不带 --no-index 时 check-ignore 退出码为 1、无输出 —— 这正是“已跟踪文件
#    不受 ignore 影响”的证据（ignore 只挡未跟踪文件）
git check-ignore -v design/OpenList-Client-Design.html; echo "exit=$?"
# 预期：exit=1

# 4) design/ 下新增的临时副本会被规则挡住
touch design/tmp-export.png
git check-ignore -v design/tmp-export.png
# 预期：.gitignore:43:design/	design/tmp-export.png
rm design/tmp-export.png
```

本地（验证构建侧隔离，任选其一）：

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64

# 1) 资源目录里不应出现设计稿
find build/flutter_assets -iname '*design*'
# 预期：无输出

# 2) 资源清单不应声明设计稿
grep -i "OpenList-Client-Design" build/flutter_assets/AssetManifest.json
# 预期：无输出（退出码 1）

# 3) APK 包内不应包含设计稿
unzip -l build/app/outputs/flutter-apk/app-release.apk | grep -i "OpenList-Client-Design"
# 预期：无输出
```

CI 侧：查看 cnb.cool 该次构建的 `build-android` 阶段日志，末尾应出现

```
== 设计稿隔离校验 ==
设计稿已入库（仅文档用途），大小 278376 字节
OK: 设计稿未进入任何构建产物
```

若出现 `FAIL: APK 中出现设计稿`，流水线会直接失败——这就是“构建确实忽略设计稿”的可执行证据。

### 可选：连构建都不触发

如果只想在源码变更时才跑流水线，可在 `.cnb.yml` 顶部解开注释：

```yaml
skipIfModify:
  - design/**
  - "**/*.md"
```

（默认保持注释状态，避免不同 CNB 版本对路径过滤支持不一致导致流水线无法启动。）

## 构建

> 本仓库不在本地编译，所有构建都在 cnb.cool 流水线完成。

### Android（CI 产出）

`.cnb.yml` 在 `main` 分支推送后执行：

1. `flutter analyze`（提示性，不阻塞）
2. `flutter build apk --release --target-platform android-arm64`

产物：`build/app/outputs/flutter-apk/app-release.apk`（release 使用 debug 签名，便于安装验收；正式发布请替换 keystore）。

### Windows（本机或 Windows runner）

Windows 的 C++ runner 由 Flutter 官方模板生成，避免手写 runner 与 Flutter 版本错配：

```powershell
flutter pub get
.\tool\bootstrap_windows.ps1          # 生成 windows/ 平台目录
flutter run -d windows                # 开发
.\tool\package_windows.ps1 -Version 1.0.0   # 便携版 zip + 安装版（需 Inno Setup 6）
```

单实例、托盘、关闭到托盘、窗口尺寸限制均在 Dart 层完成，无需改动生成的 runner。

## 本地存储键

| 键 | 内容 |
| --- | --- |
| `ol_servers_index` | JSON[]，仅 id / 名称 / 地址 / 偏好，无密码 |
| `ol_active_server_id` | 当前实例 |
| `ol_srv_<id>_token` | 系统安全存储（Credential Manager / Keystore） |
| `ol_srv_<id>_download` | 独立下载目录 |
| `ol_srv_<id>_browse` | 浏览位置与排序 |
| `ol_srv_<id>_favorites` | 收藏 |
| `ol_srv_<id>_recent` | 最近访问目录 |
| `ol_srv_<id>_resume` | 播放进度 |
| `ol_srv_<id>_cache\|<path>` | 目录离线缓存 |
| `ol_prefs` | 主题、并发、限速、托盘偏好 |
| `ol_transfers` | 未完成的传输任务 |

密码与 Token 不写入 prefs、日志或崩溃上报。

## API 契约

统一使用用户填写的 Base URL，自动兼容子路径部署（`https://host/openlist`）。请求头 `Authorization: <token>`，业务错误统一 `{code,message}`，401 回登录、403 权限、404 路径失效、429 退避。

```
POST /api/auth/login        POST /api/fs/list        POST /api/fs/search
GET  /api/me                POST /api/fs/get         POST /api/fs/dirs
PUT  /api/fs/put            POST /api/fs/mkdir       POST /api/fs/rename
POST /api/fs/move           POST /api/fs/copy        POST /api/fs/remove
POST /api/share/create      GET  /api/share/list     POST /api/share/delete
POST /api/fs/add_offline_download   GET /api/task/list
GET  /api/admin/storage/list        GET /api/public/settings
GET  /d/<path>?sign=<sign>          （Range 直读，下载与播放共用）
```

## 验收对照

| 模块 | 结果 |
| --- | --- |
| 连接 | 地址可达 / TLS / 版本 / 2FA 全路径，失败内联提示；Token 可续签（401 自动清凭据回登录） |
| 服务器 | 添加 / 编辑 / 删除 / 切换，数量不限，隔离目录生效，删除当前自动切到最近实例 |
| 文件 | 分页、面包屑、刷新、排序、多选、批量移动/复制/删除、拖拽上传、四态齐全 |
| 搜索 | 300ms 防抖、scope 0/1、结果可定位、无索引降级提示 |
| 传输 | 暂停/继续/重试、重启续传、限速、并发、托盘速率状态 |
| 播放 | Range seek、字幕、断点续播、倍速，非阻塞 UI |
| 主题 | 默认跟随系统，播放器强制深色 |
| 托盘 | 四态图标、左键打开、右键菜单、关闭收进托盘、单实例、仅「退出」结束进程 |
| 安全 | 凭据仅入系统安全存储，日志与 prefs 无明文，HTTP 仅内网 |
