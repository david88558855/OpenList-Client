# OpenList Client 项目介绍

> Windows 便携版 + Android 的 OpenList（AList 系服务端）桌面/移动客户端。
> 一个代码库同时产出 `Windows x64 便携版 zip` 与 `Android arm64 APK`。

---

## 1. 项目用途

对接自建的 OpenList / AList 服务端（`/api/*` v4 接口），提供比网页更顺手的文件管理体验：

- 多实例管理（不限数量，凭据逐实例隔离，可随时切换）
- 文件浏览 / 搜索 / 批量操作（含批量下载）/ 离线下载
- 上传下载队列（断点续传、并发与限速、重启续传）
- 内置视频/音频/图片/文本播放与预览（续播、倍速、字幕）
- Windows 常驻托盘、关闭收窗、单实例

不做的事：管理后台写操作（创建存储、用户、索引一律跳浏览器）、自建账号体系、云同步。

---

## 2. 技术栈与关键依赖

| 类别 | 选型 | 用途 |
|---|---|---|
| 框架 | Flutter 3.47.7（stable） | 单一代码库产出 Windows / Android |
| 状态 | `flutter_riverpod ^2.5.1` | Provider 图 + StateNotifier 控制器 |
| 路由 | `go_router ^14.2.0` | 声明式路由、深链、重定向 |
| 网络 | `dio ^5.4.3` | 拦截器、流式下载、CancelToken |
| 播放 | `media_kit` / `media_kit_video` / `media_kit_libs_video` | 流式播放、Range seek |
| 桌面壳 | `window_manager ^0.4.2`、`tray_manager ^0.2.3` | 无边框窗口、托盘四态图标 |
| 存储 | `shared_preferences`（Android）、便携 JSON（Windows）、`flutter_secure_storage`（凭据） | 配置与密钥分离 |
| 其它 | `file_picker`、`url_launcher`、`desktop_drop`、`flutter_svg`、`path_provider` | 选目录、开浏览器、拖拽上传、矢量图标 |

---

## 3. 整体架构

```
lib/
├── main.dart                # 启动：单实例 → 窗口/托盘 → Prefs → boot() → runApp
├── app/
│   ├── app.dart             # MaterialApp.router、主题、字号缩放（桌面 1.12 / 安卓 1.30）
│   ├── router.dart          # 全部路由 + 登录态重定向
│   ├── frame.dart           # 页面外壳：标题栏 / 底部导航 / 返回键 / goBackOrFiles()
│   └── providers.dart       # Provider 图：prefs/session/files/transfers/settings/favorites
├── core/
│   ├── api/                 # OpenListApi（Dio 封装）+ ApiException
│   ├── models/              # ServerProfile / FileItem / TransferTask / ShareInfo…
│   ├── storage/             # Prefs（便携 JSON）、ServerStore（键约定）、SecureStore、下载路径
│   ├── theme/               # tokens（调色板/字号/尺寸）、ThemeData、系统栏样式
│   ├── widgets/             # 设计系统：ol_controls / ol_dialogs / ol_icon / file_widgets / workspace_nav
│   └── format.dart          # 字节、时间、路径
├── features/                # 按业务切分：auth / files / transfers / search / media / servers / settings
│   ├── files/parts/         # 文件页按职责拆出的部分（part of files_page.dart）
│   └── settings/parts/      # 设置页按分区/移动端拆出的部分（part of settings_page.dart）
└── platform/windows/        # tray.dart（托盘）、single_instance.dart（文件锁单实例）
```

**数据流**：`UI (ConsumerWidget)` → `StateNotifier`（files/transfers/session…） → `OpenListApi`；
持久化统一走 `Prefs`（键名固定：`ol_servers_index` / `ol_active_server_id` / `ol_srv_<id>_*` / `ol_prefs` / `ol_transfers`），
密钥只进系统安全存储。

---

## 4. 主要模块与核心功能

| 模块 | 文件 | 核心功能 |
|---|---|---|
| 认证与会话 | `features/auth/session.dart`、`login_page.dart` | 地址探测（`/api/public/settings`）、密码 / API Token / 两步验证、离线态保留、401 才登出 |
| 文件管理 | `features/files/files_page.dart` | 面包屑、分页滚动（100/页）、排序筛选、列表/网格、多选批量、拖拽上传、右键/三点菜单、四态（空/骨架/错误/离线） |
| 文件操作 | `file_actions.dart` | 上传、新建目录、重命名、删除、移动/复制（目录选择器）、单文件下载、批量下载、离线下载、预览 |
| 传输中心 | `features/transfers/*` | 队列调度（并发可调）、Range 续传、暂停/继续/重试、限速（逐块重读，实时生效）、磁盘持久化、服务端离线任务 |
| 搜索 | `features/search/search_page.dart` | `Ctrl K` 命令面板、300ms 防抖、当前目录 / 全部挂载、键盘上下选择 |
| 播放器 | `features/media/player_page.dart` | 强制深色、续播、倍速、音量、同目录播放列表、字幕自动挂载 |
| 收藏 | `features/files/favorites_page.dart` | 本地收藏（按实例隔离），支持批量下载 |
| 服务器管理 | `features/servers/*` | 列表 + 同屏编辑、显示名称唯一（地址可重复）、导入/导出配置（JSON，不含密码） |
| 设置 | `features/settings/*` | 下载目录、传输、播放与预览、外观、关于与更新；侧栏可跳服务器管理 |
| 桌面集成 | `platform/windows/*` | 托盘四态图标与菜单（双击显示）、关闭收窗、单实例（文件锁 + UDP 唤醒） |

**导航约定**：文件 / 传输 / 收藏 / 设置 / 服务器管理都是**一级独立页面**，各自带返回；
桌面统一「工作区导航」（所有文件 → 收藏 → 传输任务 → 设置），各页面共用一份组件，切页不重排。

---

## 5. 运行与构建

### 本地开发

```bash
flutter pub get
flutter run -d windows      # 或 -d <android-device>
flutter analyze             # 只阻断 error
```

要求 Flutter 3.47.7（与 CI 一致）。Windows 需要 VS「使用 C++ 的桌面开发」+ Windows 10 SDK。

### 云端构建（本项目默认方式）

本项目**不在本地编译**，一律走 GitHub Actions（`.github/workflows/build.yml`）：

| 触发 | 产物 |
|---|---|
| push 到 `main` | `static check`（analyze）→ `android-arm64` APK → `windows-x64-portable` zip（均作为 Artifacts） |
| 推送 `v*` tag | 同上，并额外把 apk / zip / sha256 发布到 GitHub Release |

构建脚本：`tool/ci_build_android.sh`、`tool/ci_build_windows.ps1`（产物命名 + sha256）。

### 便携版数据位置

Windows 下配置写在 `<主程序目录>/userdata/prefs.json`，整个目录拷走即带走配置；
程序目录不可写时退到 `%LOCALAPPDATA%\OpenListClient\userdata\`。
密码 / Token 在系统安全存储，换机器需重新登录一次（服务器列表仍在）。

---

## 6. 关键约定（改代码前请先读）

1. **禁止页面转场动画**：`PageTransitionsTheme` 全平台映射到 `_NoTransitionBuilder`，不要加淡入/上滑/缩放。
2. **路由 `/settings` 的 `tab` 用 `root` 哨兵**：Android 靠它显示「我的」根列表，桌面把它归一化为外观分区。
3. **返回统一走** `lib/app/frame.dart` 的 `goBackOrFiles(context)`：能 pop 就 pop，否则回 `/files`。
4. **左栏导航只有一份**：`core/widgets/workspace_nav.dart`，不要在页面里再手写导航项（上一版就是这么错位的）。
5. **密钥永不进 prefs.json**，只走 `SecureStore`。
6. 版本号有「一致性」检查：`pubspec.yaml` 与 `lib/core/app_info.dart` 必须同时改。
