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
tool/             # Windows 平台引导与打包脚本
installer/        # Inno Setup 安装版脚本
.cnb.yml          # 云端构建流水线
```

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
