# Changelog

## v1.0.2 · 2026-10-19

### 交互调整
- **服务器入口收敛**：登录页去掉「我的服务器」列表，只留一个「服务器管理」入口；已登录界面的
  标题栏 / 手机端服务器芯片不再展开列表，点击直接进入服务器管理页。
- **服务器管理**：整行 / 整卡可点 = 切换为当前实例并打开它上次浏览的文件夹；按钮文案由
  「切换 / 连接」改为「打开」，异常服务器保留「重连」。
- **文件页**：新建文件夹 / 上传文件 / 离线下载收进右下角 58px 主按钮（展开时旋转 45° 变
  `×`），右上角只保留搜索与刷新。
- **底部 Tab**：「我的」改为「设置」。
- **面包屑**：手机端路径字号 9 → 12.5px、数量 9 → 11.5px，桌面端 11.5 → 13px（当前段 14px）；
  点任意上级段落直接跳转。

### 设置页
- 新增「服务器管理」入口（直达 A8/W8）。
- 新增「下载目录」：底部面板显示当前路径、可用操作（选择目录 / 恢复默认）；
  Android 11+ 需「所有文件访问权限」，提供「去授权」跳系统授权页，未授权时行内标红「需授权」。
  选择目录走 SAF 目录选择器，选择结果按实例持久化，下载优先写到该目录。

### 构建
- 构建迁到 GitHub Actions（`.github/workflows/build.yml`）：`ubuntu-latest` 出 Android arm64 APK，
  `windows-latest` 出 Windows x64 便携包；打 tag 自动发 Release。CNB 流水线（`.cnb.yml`）已移除。

### 产物
- 只产出两种：`OpenList-Client-<ver>-android-arm64.apk`、
  `OpenList-Client-<ver>-windows-x64-portable.zip`。
- **Windows 安装程序永久移除**：删除 `installer/`（Inno Setup）、`package_windows.ps1` 仅保留便携版打包。
- 设计稿同步：发行形态、版本号、构建产物命名均与本次产物一致。

## v1.0.1 · 2026-10-19

### 修复
- **安卓内容压到状态栏**：全平台统一 edge-to-edge（`SystemChrome.setEnabledSystemUIMode`），
  `AppFrame` 统一用 `MediaQuery.padding` 的顶部内边距避让状态栏与刘海；已补的内边距会从
  子页面的 `MediaQuery` 中移除，页面自己再读 padding 也不会重复留白。
- **安卓底部多余白条**：状态栏与导航栏改为透明、图标亮度跟随主题；底部导航条改用
  `viewPadding` 撑满系统导航栏/手势条区域（键盘弹出时不叠加内边距）。Android 主题里的
  `statusBarColor` / `navigationBarColor` 同步设为透明，启动阶段不再闪出系统默认白底。
- 登录页、播放页这类恒定深色界面单独声明浅色系统栏图标，避免深色背景下图标不可见。
- 设置页个人资料（深色渐变头部）保留自绘到状态栏下方的效果，由页面自己避让。

### 移除
- 登录页「扫码授权」入口及其提示文案；图标集里的 `qr` 字形一并删除（该能力此前只是占位，
  并无实际扫码实现）。

## v1.0.0 · 2026-10-19

首个可交付版本。按设计稿 `design/OpenList-Client-Design.html` v1.3 的 W1–W9 / A1–A8 画板实现，
Flutter 3.x 单代码库，Windows 10/11 与 Android 8.0+ 同源。

### 连接与多服务器
- 地址探测（`/api/public/settings`）显示站点名与版本，失败内联提示、不弹窗
- 密码登录 / API Token / 两步验证码；HTTP 仅内网地址放行
- 服务器数量不限；凭据写入系统安全存储，下载目录、媒体缓存、浏览位置按实例隔离
- 删除当前实例自动切换到最近实例；切换时可暂停旧任务

### 文件与搜索
- 目录浏览：分页（100/页，滚动续载）、面包屑、刷新、按名称/大小/时间排序、类型筛选、列表/网格
- 多选与批量操作：下载、删除、移动、复制；新建文件夹、重命名、分享（有效期 + 提取码）、离线下载
- 拖拽上传（Windows）、右键菜单、快捷键 Ctrl K / Ctrl U / Ctrl Shift N / F2 / Delete / F5 / Space
- 四态齐全：空目录、400ms 骨架屏、失败横幅（重试 + 诊断）、离线读缓存
- 搜索：300ms 防抖，当前目录 / 全部挂载两种 scope，键盘 ↑↓ + Enter

### 传输
- 下载：Range 续传、暂停/继续/重试、重启后从已写入字节继续
- 上传：`PUT /api/fs/put` + `File-Path`，进度实时回显
- 实时速率、并发数（1/2/4/6）、下载限速、任务持久化（`ol_transfers`）

### 播放
- media_kit（libmpv）流式播放，Range seek
- 断点续播、倍速（0.75×–2×）、音量、同目录播放列表、同目录字幕自动挂载

### Windows 集成
- 自绘标题栏（拖动 / 最小化 / 最大化 / 关闭）、最小窗口 1024×680
- 托盘四态图标（空闲 / 传输中 / 失败 / 已暂停）、右键菜单、关闭收进托盘、UDP 单实例
- 仅「退出」结束进程

### 安全与边界
- 密码仅登录时使用一次；Token 只进 Credential Manager / Keystore，不写 prefs、日志、崩溃上报
- 管理后台只读（`/api/admin/storage/list`），写操作跳浏览器
- 不做：iOS / macOS / Linux、自建账号、云同步、WebView 外壳

### 构建与产物
- CNB 流水线：`flutter analyze`（提示性）+ `flutter build apk --release --target-platform android-arm64`
- 工具链：Gradle 8.14.3 / AGP 8.11.1 / Kotlin 2.2.20 / compileSdk 36 / minSdk 26 / NDK 28.2
- 产物：`dist/OpenList-Client-1.0.0-android-arm64.apk` + `.sha256`，作为 Release 附件发布
- 设计稿隔离：assets 白名单 + analyzer exclude + 构建后产物反查

### 已知限制
- Android 画中画、前台服务通知栏进度、压缩下载（ZIP）、多窗口、内置更新器未纳入本版
- Windows 安装版 / 便携版脚本已就绪（`tool/package_windows.ps1` + `installer/openlist-client.iss`），
  需在 Windows 机器上执行；本仓库不在 Linux CI 交叉编译 Windows
- Release APK 使用 debug 签名，便于安装验收；正式分发请替换 keystore
