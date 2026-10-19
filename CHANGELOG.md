# Changelog

## v1.0.5 · 2026-10-19

### 修复（阻塞验收）
- **K-01 托盘图标不显示**：`tray_manager` 在 Windows 上走
  `LoadImage(..., IMAGE_ICON, ..., LR_LOADFROMFILE)`，**只认 ICO/BMP**，之前的 PNG
  得到 NULL HICON，通知区域只剩空白占位。现在 `tool/gen_app_icons.py` 为四态各生成
  多尺寸 ICO（16/20/24/32/48，覆盖 100%–200% DPI），`TrayService` 在 Windows 用
  `.ico`、失败自动重试三次；CI 增加「托盘四态 ICO 存在且合法」门禁。
- **K-02 退出需多次点击**：根因是 `tray_manager` 0.2.x 的 Windows 插件在
  `_methodCallHandler` 里已经调用过 `MenuItem.onClick`，而本项目的
  `onTrayMenuItemClick` 又调用了一次，退出动作被触发两遍。现在动作只由菜单驱动，
  退出路径改为**幂等、单次、按序**：断开订阅 → 取消关闭拦截 → `NIM_DELETE` →
  destroy 窗口 → `exit(0)`，每步都有超时兜底。
- **K-03 图标同源回归**：exe 图标与 Android 启动图标继续由同一套几何数据生成，
  构建脚本复制 `assets/windows/app_icon.ico` 到 runner 资源；文档补充四项同源核对。

### 修复（编译与运行）
- 修正上一版遗留的 19 处编译错误：非法字重 `FontWeight.w550/w650/w750`、
  `List` 上调用不存在的 `forServer()/isFavorite()`、`void` 返回值被 `await`、
  `||` 右操作数不是 bool。
- 侧栏挂载点跳转失效：`/files?path=` 复用同一路由时 `initState` 不会重跑，
  补 `didUpdateWidget` 响应新路径。
- 搜索页 scope 语义反了：「当前目录」被当成全盘搜索、「全部挂载」只在根目录找；
  现按接口语义（0 全部 / 1 当前目录）映射，定位后带路径回文件页。
- 客户端版本号统一到 `AppInfo`，清理设置页/侧栏硬编码的 1.0.3。

### 设计稿
- `design/OpenList-Client-Design.html` 同步为最新的 v2.0 交付版（仅文档用途，
  构建全链路排除）。

## v1.0.4 · 2026-10-19

### 布局与功能一致性（对齐设计稿）
- **A3 传输页**：分段标签改为「进行中 N / 已完成 N / 失败 N」深色药丸 + 右侧「全部暂停 ›」；
  任务卡结构对齐（图标 + 名称 + 路由速度 + 百分比 / 进度条 / 底部 bytes·剩余）；
  新增「刚刚完成」分区与「仅在 Wi-Fi 下传输 / 后台保持传输」开关卡（持久化）。
- **A2 文件页**：筛选 chips 收敛为 全部 / 视频 / 图片 / 文档（去掉音频）；存储卡副行改「已用 X · N%」。
- **A7 长按面板**：补「压缩下载（ZIP）」行，动作结构对齐设计（播放/下载/分享/收藏 + 重命名/移动/复制/压缩/删除）。
- **A6 设置页**：条目与分组一一对齐设计稿。

### 设置
- `AppSettings` 新增 `wifiOnly` / `backgroundTransfer` 字段（含持久化与 setter）。

### 设计稿
- 重新整理为全新单文件设计稿（v2.0）：统一布局与功能口径、8 个移动端画板 A1–A8、
  76 枚线性 SVG 图标、设计令牌与关键尺寸表；**永久不含 Windows 安装包表述**。

## v1.0.3 · 2026-10-19

### Windows 托盘（按新规格）
- 右键菜单收敛为两项：**显示主界面** / **退出**。
- **左键双击**显示主界面（单击不动作）。
- 关闭窗口、Alt+F4、任务栏关闭一律只收进托盘；**只有菜单「退出」结束进程**（原「关闭到托盘」开关改为固定行为说明）。
- 托盘图标与应用图标统一为 Android 启动图标的深蓝底 + 三层轮廓。

### 图标
- 新增 `tool/gen_app_icons.py`，从 Android 自适应图标的同一套几何数据生成
  `assets/windows/app_icon.ico`（16–256 共 7 档，32 位 BMP）与托盘四态 PNG；
  构建时自动替换 `windows/runner/resources/app_icon.ico`，exe 图标与安卓版一致。

### 界面一致性
- 文件页存储卡片整卡可点：进入对应挂载点，右上角加箭头（与设计稿 A2 一致）。
- 设计稿 W9 托盘段同步：菜单两项、双击显示、图标同源。

### 修复
- Windows 便携包版本号解析失败导致产物名变成 `0.0.0`（改为读取 pubspec 的 `version:`）。

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
