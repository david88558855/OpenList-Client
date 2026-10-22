# OpenList Client

> OpenList（AList 系服务端）的 **Windows 便携版 + Android** 客户端。
> 一套 Flutter 代码库同时产出 `windows-x64-portable.zip` 与 `android-arm64.apk`，纯原生渲染，不使用 WebView 包裹网页。

---

## 1. 项目定位

面向自建 OpenList / AList 实例的桌面与移动客户端，解决网页端在「批量文件操作、传输队列、播放预览、常驻使用」上的体验短板：

- **桌面**：常驻托盘、关闭收窗、单实例、拖拽上传、右键菜单、快捷键、便携存储（配置随程序目录走）。
- **移动**：底部 Tab（文件 / 传输 / 收藏 / 设置）、长按批量、下拉刷新、FAB 上传。
- **管理后台只读**：创建存储、用户、索引等写操作一律跳浏览器完成，客户端不承担后台管理职责。

## 2. 主要功能

| 模块 | 能力 |
|---|---|
| 登录 | 地址探测（`/api/public/settings`）、密码登录、API Token、两步验证码、内联错误提示、HTTP 仅内网放行 |
| 多服务器 | 数量不限；**显示名称唯一、地址可重复**（同一实例可存多条不同账号/备注）；逐实例隔离下载目录与浏览位置；切换时可暂停旧任务；删除只移除本地配置 |
| 文件浏览 | 分页（100/页，滚动续载）、面包屑、刷新、按名称/大小/修改时间排序、类型筛选、列表/网格、批量选择、拖拽上传、右键与三点菜单 |
| 文件操作 | 上传、新建文件夹、重命名、删除、移动/复制（目录选择器）、下载、离线下载、预览 |
| 四态 | 空目录、骨架屏（400ms 延迟出现）、连接失败（含重试）、离线（读本地缓存） |
| 搜索 | `Ctrl K` 命令面板、300ms 防抖、当前目录 / 全部挂载、键盘 ↑↓ + Enter |
| 传输 | 下载（Range 续传 + 完整性校验）、上传、暂停/继续/重试、并发数、上下行限速（改完即时生效）、任务持久化、服务端离线任务列表 |
| 播放 | media_kit 流式播放、续播、倍速、音量、同目录播放列表、同目录字幕自动挂载、播放失败可重试 |
| 收藏 | 按实例存在本地，可批量下载；不写入服务端 |
| 桌面集成 | 托盘四态图标、双击显示主界面、关闭收窗、单实例（文件锁 + UDP 唤醒）、自绘标题栏 |

## 3. 平台与运行环境

| 项 | 要求 |
|---|---|
| Windows | 10 / 11 x64，解压即用（无需安装） |
| Android | 8.0+（`minSdk 26`，`targetSdk 36`，`compileSdk 36`） |
| 服务端 | OpenList / AList，接口 `/api/*` v4；支持子路径部署（`https://host/openlist`） |
| 构建工具 | Flutter `3.47.7` stable（与 CI 一致） |

## 4. 快速开始

### 4.1 获取客户端

从 [Releases](https://github.com/david88558855/OpenList-Client/releases) 下载：

| 平台 | 文件 | 说明 |
|---|---|---|
| Windows | `OpenList-Client-<ver>-windows-x64-portable.zip` | 解压到任意目录运行 `OpenList.exe`；配置写在同级 `userdata/` |
| Android | `OpenList-Client-<ver>-android-arm64.apk` | debug 签名，可直接安装 |

每个产物都附带 `.sha256`，可比对（Windows：`certutil -hashfile <文件> SHA256`；Android：`sha256sum`）。

### 4.2 首次连接

1. 启动后进入登录页，填服务器地址（可省略 `https://`，子路径直接写 `https://host/openlist`）。
2. 选择认证方式：**密码**（默认 `admin` + 服务端密码，可填两步验证码）或 **API Token**。
3. 勾选「保持登录」后凭据写入系统安全存储（Windows Credential Manager / Android Keystore）。
4. 已保存过的实例会出现在「服务器管理」里，点击即可切换；登录页也会预填最近一次的地址。

### 4.3 常用操作

| 操作 | Windows | Android |
|---|---|---|
| 打开文件 | 单击文件弹菜单；双击文件夹进入 | 点击行（弹出操作面板），文件夹直接进入 |
| 更多操作 | 行尾 `⋯` 或右键 | 行尾 `⋯` |
| 搜索 | `Ctrl K` 或顶部搜索框 | 顶部搜索图标 |
| 刷新 | `F5` | 下拉刷新 |
| 全选 / 取消选择 | `Ctrl A` / `Esc` | 批量模式「全选」 |
| 删除选中 | `Delete` | 批量条「删除」 |
| 上传 | 右上「上传」或拖拽文件进窗口 | 右下 `+` |

## 5. 配置说明

### 5.1 设置项

| 分区 | 内容 |
|---|---|
| 下载目录 | 按实例选择的下载路径；Android 默认公共 `Download/OpenList`，可选独立目录 |
| 传输 | 并发任务数（1–8，默认 3）、下载/上传限速、任务完成通知、后台保持传输 |
| 播放与预览 | 断点续播、自动播放下一集、切换时暂停、默认倍速 |
| 外观 | 跟随系统 / 浅色 / 深色 |
| 关于与更新 | 版本、服务端版本、**数据目录**（便携或系统存储）、项目主页 |
| 服务器管理 | 独立页面：添加 / 编辑 / 删除 / 切换、测试连接、导入导出配置（JSON，不含密码） |

> 桌面端「设置」入口在工作区「传输任务」之下；「设置」与「服务器管理」是两个各自带返回的一级页面。

### 5.2 便携存储（Windows）

- **权威文件**：`<主程序目录>/userdata/prefs.json`，路径由 `Platform.resolvedExecutable` 的父目录解析（与当前工作目录无关）；整个目录拷走配置即跟着走。
- **兜底**：程序目录不可写（如解压到 `Program Files`）时退到 `%LOCALAPPDATA%\OpenListClient\userdata\prefs.json`。设置 → 关于 → **数据目录**会显示实际位置与「便携 / 系统」。
- **写入方式**：内存 Map + 250ms 合并落盘，`tmp → rename` 原子替换（旧文件先转 `.bak`，失败可回滚）；托盘「退出」前强制 `flush()`。
- **配置来源唯一化**：仅当主程序目录下存在 `prefs.json` 时才加载；目录下没有该文件即视为无配置，
  **不从旧版本或系统用户目录移植任何数据**。文件损坏会备份为 `prefs.json.bak` 并当作无配置，绝不从别处补齐。
- **不随目录迁移**：密码 / Token 只在系统安全存储，换机器或换目录后需重新登录一次（服务器列表仍在，登录页会带出地址）。Android 仍使用应用私有目录。

### 5.3 本地存储键

| 键 | 内容 |
|---|---|
| `ol_servers_index` | JSON[]，id / 名称 / 地址 / 偏好（无密码） |
| `ol_active_server_id` | 当前实例 |
| `ol_srv_<id>_token` | 系统安全存储（不在 prefs 中） |
| `ol_srv_<id>_download` | 该实例的下载目录 |
| `ol_srv_<id>_browse` | 浏览位置与排序 |
| `ol_srv_<id>_favorites` | 收藏 |
| `ol_srv_<id>_resume` | 播放进度 |
| `ol_srv_<id>_cache\|<path>` | 目录离线缓存 |
| `ol_prefs` | 主题、并发、限速、播放偏好 |
| `ol_transfers` | 未完成的传输任务 |

## 6. 目录结构

```
lib/
  main.dart                    # 启动：单实例 → 窗口/托盘 → Prefs → boot() → runApp
  app/
    app.dart                   # MaterialApp.router、主题、字号缩放
    router.dart                # 全部路由 + 登录态重定向
    frame.dart                 # 页面外壳（标题栏/底部导航/返回键）、goBackOrFiles()
    providers.dart             # Provider 图
  core/
    api/                       # OpenListApi（dio 封装）、ApiException
    models/                    # ServerProfile / FileItem / TransferTask / ShareInfo
    storage/                   # Prefs（便携 JSON）、ServerStore、SecureStore、下载路径
    theme/                     # tokens / ThemeData / 系统栏样式
    widgets/                   # ol_controls / ol_dialogs / ol_icon / file_widgets / workspace_nav
    format.dart                # 字节、时间、路径格式化
  features/
    auth/                      # 登录页、会话（SessionNotifier）
    files/                     # 文件页（含 parts/）、收藏、文件操作、controller
    transfers/                 # 传输页与队列 controller
    search/                    # 搜索页
    media/                     # 播放器
    servers/                   # 服务器管理、编辑页、表单
    settings/                  # 设置页、侧栏、下载目录
  platform/windows/            # tray.dart（托盘）、single_instance.dart（单实例）
android/                       # Android 工程（minSdk 26 / compileSdk 36）
assets/tray/                   # 托盘四态图标（.ico 供 Windows，.png 备用）
assets/windows/app_icon.ico    # exe 图标（构建时注入 Windows runner）
tool/                          # 平台引导、图标生成、CI 构建脚本
docs/                          # PROJECT.md（架构）、CODE-REVIEW.md（审查报告）
.github/workflows/build.yml    # analyze + Android APK + Windows 便携包 / Release 发布
```

### 路由表

| 路径 | 页面 |
|---|---|
| `/login` | 登录 |
| `/files` | 文件（根路由 `/` 重定向至此） |
| `/transfers` | 传输 |
| `/favorites` | 收藏（旧链接 `?tab=recent` / `?tab=share` 会重定向回收藏） |
| `/search` | 搜索 |
| `/settings` `/settings/:tab` | 设置（`tab=root` 在 Android 显示「我的」列表） |
| `/servers` `/servers/edit/:id` | 服务器管理 / 编辑 |
| `/player` | 播放器（`?path=` 指定媒体） |

## 7. 开发与构建

### 7.1 本地开发

```bash
flutter pub get
flutter run -d windows          # 或 -d <android-device>
flutter analyze                 # 只阻断 error
```

Windows 需要 Visual Studio「使用 C++ 的桌面开发」+ Windows 10 SDK；`windows/` 平台目录不入库，首次可用：

```powershell
.\tool\bootstrap_windows.ps1    # 生成 windows/ 平台目录
.\tool\package_windows.ps1      # 打便携版 zip（产物在 dist/）
```

### 7.2 CI 构建（本仓库默认方式）

`.github/workflows/build.yml` 三个 job：

| job | 内容 |
|---|---|
| `static check` | `flutter pub get` → `flutter analyze --no-fatal-warnings --no-fatal-infos`；额外断言托盘四态 `.ico` 存在、`pubspec.yaml` 与 `lib/core/app_info.dart` 版本号一致 |
| `Android arm64 APK` | `tool/ci_build_android.sh` → `flutter build apk --release --target-platform android-arm64`，上传 `android-arm64` artifact |
| `Windows x64 portable` | `tool/ci_build_windows.ps1` → `flutter build windows --release`，打包 `windows-x64-portable` artifact |

触发：push 到 `main`（只产出 Artifacts）、推送 `v*` tag（额外发布 GitHub Release）、或 `workflow_dispatch` 手动。发布用仓库自带 `GITHUB_TOKEN`（`permissions: contents: write`），无需额外 Secret。

### 7.3 发版流程

```bash
# 1) 改版本号（两处必须一致，CI 会校验）
#    pubspec.yaml: version: X.Y.Z+BUILD
#    lib/core/app_info.dart: version / build
# 2) 更新 CHANGELOG.md
git add -A && git commit -m "chore: release X.Y.Z" && git push origin main
# 3) 打注解 tag：正文即 Release 说明
git tag -a vX.Y.Z -F -   # 粘贴发布说明后 Ctrl+D
git push origin vX.Y.Z
```

## 8. 关键依赖

| 类别 | 依赖 | 用途 |
|---|---|---|
| 框架 | `flutter` 3.47.7 | Windows / Android 单代码库 |
| 状态 | `flutter_riverpod ^2.5.1` | Provider 图与控制器 |
| 路由 | `go_router ^14.2.0` | 声明式路由、重定向 |
| 网络 | `dio ^5.4.3` | 拦截器、流式传输、CancelToken |
| 播放 | `media_kit` / `media_kit_video` / `media_kit_libs_video` | 流式播放、Range seek |
| 桌面 | `window_manager ^0.4.2`、`tray_manager ^0.2.3` | 无边框窗口、托盘 |
| 存储 | `shared_preferences ^2.2.3`、`flutter_secure_storage ^9.2.2` | 配置（Android）与凭据 |
| 其它 | `file_picker`、`url_launcher`、`desktop_drop`、`flutter_svg`、`path_provider` | 选目录、开浏览器、拖拽、矢量图标、路径 |

## 9. 安全与数据

- 密码 / API Token **不写入** `prefs.json`、日志或崩溃上报，只进系统安全存储；凭据读取失败会自动清理坏条目并提示重新登录。
- 明文 HTTP 仅允许内网地址（`localhost` / `10.x` / `192.168.x` / `172.16-31.x` / `*.local` / `*.lan`），公网强制 HTTPS。
- 下载文件名按 `safePathSegment` 清洗（非法字符、`..`、结尾点/空格、Windows 保留设备名、超长截断），避免路径穿越与建文件失败。

## 10. 接口契约

统一使用用户填写的 Base URL（自动兼容子路径），请求头 `Authorization: <token>`，业务响应 `{code, message, data}`；`401` 清除凭据回登录，`403` 权限不足，`404` 路径失效，`429` 退避。

```
POST /api/auth/login              POST /api/fs/list            POST /api/fs/search
GET  /api/me                      POST /api/fs/get             POST /api/fs/dirs
PUT  /api/fs/put                  POST /api/fs/mkdir           POST /api/fs/rename
POST /api/fs/move                 POST /api/fs/copy            POST /api/fs/remove
POST /api/fs/add_offline_download GET  /api/task/list
GET  /api/admin/storage/list      GET  /api/public/settings
GET  /d/<path>?sign=<sign>        （Range 直读，下载与播放共用）
```

## 11. 已知限制

- 管理后台写操作不在客户端内（创建/编辑存储、用户、索引一律跳浏览器）。
- Android 未做画中画与前台服务通知，后台传输依赖系统是否回收进程。
- 搜索一次最多返回 100 条，未做翻页。
- 批量下载支持文件；**选中文件夹时当前会跳过并提示**，文件夹递归下载的方案见 `docs/FOLDER-DOWNLOAD.md`。
- 分享功能已移除（v1.0.26），`/api/share/*` 不再调用。
- 仅提供 Windows 与 Android；macOS / Linux / iOS 未构建。
- 官方 Release 的 APK 使用 debug 签名，正式分发请替换 keystore。
