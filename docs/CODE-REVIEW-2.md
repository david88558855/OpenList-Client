# 全量代码审查（第二轮）

> 范围：`lib/` 全部 49 个 Dart 文件（约 9.4k 行）、`tool/` 构建脚本、`.github/workflows/build.yml`。
> 基线：v1.0.42。上一轮审查见 [`CODE-REVIEW.md`](CODE-REVIEW.md)（32 条，已全部处理）。

---

## 0. 结论摘要

| 维度 | 结论 |
|---|---|
| 页面转场特效 | **不存在**。`PageTransitionsTheme` 全平台映射到 `_NoTransitionBuilder`，无 `Hero` / `PageRouteBuilder` / `SlideTransition` / `FadeTransition` / `ScaleTransition` |
| 组件动画 | **已全部移除**（本轮清掉最后 3 处）：开关滑块 180ms、骨架呼吸 1.4s、FAB 加号旋转 180ms |
| 高危缺陷（P0） | 本轮发现并修复 1 条：切目录保留旧列表后，加载失败不再提示 |
| 中危（P1） | 6 条，均为性能/健壮性，不影响功能正确性 |
| 规范/可维护性（P2） | 4 条，主要是颜色与字号魔法数、两个超大文件 |

---

## 1. 转场与动画（专项）

### 1.1 页面转场：已全局关闭

`lib/core/theme/theme.dart`

```dart
pageTransitionsTheme: const PageTransitionsTheme(
  builders: { ... 全平台 → _NoTransitionBuilder() },
),
```

`_NoTransitionBuilder` 的 `transitionsBuilder` 直接返回 `child`，没有任何动画包装。
全仓已无 `Hero`、`PageRouteBuilder`、`SlideTransition`、`FadeTransition`、`ScaleTransition`、
`AnimatedSwitcher`、`TweenAnimationBuilder`。

### 1.2 组件动画：本轮清空最后三处

| 位置 | 原实现 | 处理 |
|---|---|---|
| `core/widgets/ol_controls.dart` `OlSwitch` | `AnimatedContainer` + `AnimatedAlign`（180ms 滑块滑动） | 改为 `Container` + `Align`，瞬时切换 |
| `core/widgets/ol_controls.dart` `OlSkeleton` | `AnimationController(1.4s)..repeat(reverse: true)` 呼吸 | 改为 `StatelessWidget` + 静态色块 |
| `features/files/parts/files_mobile.dart` `_Fab` | `AnimatedRotation`（展开时 + 号转 45°） | 改为静态 `OlIcon`，展开状态仍由点击切换 |

### 1.3 仍存在的系统级动画（有意保留）

| 组件 | 说明 | 是否属于「转场特效」 |
|---|---|---|
| `RefreshIndicator`（移动端下拉刷新） | 手势触发的刷新指示器 | 否，是操作反馈 |
| `CircularProgressIndicator` | 加载状态指示 | 否，是状态指示 |
| `showDialog` 默认淡入 | Flutter 框架默认 dialog 路由 | 边界情况：若要求「零动画」，需 `showGeneralDialog(transitionDuration: Duration.zero)` 全量替换 12 处对话框 |

**建议**：前两类建议保留（去掉会让"正在加载/正在刷新"无法感知）。
第三类要彻底静态化，可用 `showGeneralDialog` 包一层工具函数统一替换，改动 12 处、风险低，
但体验上对话框会"瞬间出现"，需你确认是否要做。

---

## 2. P0：已修复

### 2.1 切目录保留旧列表后，加载失败不再有任何提示

**位置**：`features/files/files_page.dart`（桌面 `_buildBody`、移动端 sliver 链）

**问题**：v1.0.38 为了消除切换闪烁，`open()` 不再清空 `items`。但页面判断错误用的是
`items.isEmpty && state.error != null` —— 保留旧列表后 `items` 非空，这个分支永远不成立，
于是「进入新目录失败」时用户看到的是**上一个目录的内容**，没有任何错误提示，也没有重试入口。

**修复**：新增 `_InlineErrorBar`（`parts/files_desktop_chrome.dart`），条件改为
「`error != null` 且 `items` 非空」时在列表上方显示一条紧凑红条（原因 + 重试）。
桌面放在 `Column[错误条, Expanded(列表)]`；移动端作为独立 sliver（不能放进 `else` 链，
否则会把列表吃掉）。

---

## 3. P1：建议尽快处理

### 3.1 `transfers_page.dart`（1227 行）/ `servers_page.dart`（940 行）未拆分
文件页与设置页已用 `part` 拆到 90~380 行，这两个文件仍是单文件巨石，阅读与改动成本高。
建议同样按「页面壳 / 列表行 / 面板 / 移动端」拆到 `parts/`，零逻辑改动。

### 3.2 启动时两个请求串行
`features/auth/session.dart` `boot()`：

```dart
final user = await api.me();
final site = await api.publicSettings();
```

两个 RTT 串行。可改为 `(api.me(), api.publicSettings()).wait` 并行，但要注意：`Future.wait`
会把异常包成 `ParallelWaitError`，当前 `on ApiException catch` 捕获不到，会误进「离线模式」。
建议：`me()` 为主（决定 401），`publicSettings()` 用 `try/catch` 包住单独吞异常，仍可并行。

### 3.3 递归扫描缺目录间节流
`features/files/file_actions.dart` `_scanFolders`：每页之间 `await 80ms`，但**目录之间没有间隔**。
深层目录会连续发 `list`，容易触发服务端限流（表现为「N 个目录读取失败」）。
建议目录切换处也加 40ms，并把 80/40 提为常量。

### 3.4 `TransfersState` 的派生列表每次都重算
`active/queued/paused/done/failed` 都是 `tasks.where(...).toList()`，而 `_tick()` 每秒调用、
`_pump()` 每任务调用 —— 任务多时是重复 O(n) 分配。
建议在 state 里维护计数，或把过滤结果缓存到 notifier 字段（任务增删时更新）。

### 3.5 单任务结束仍触发全量落盘
`_persist()` 会序列化**全部**任务。批量入队已改 `schedule: false` 节流，但 `_run` 的 `finally`
仍对每个任务 `_persist()` 一次：1000 个任务 = 1000 次全量序列化。
建议：`_persist` 内部改为 500ms debounce（prefs 本身已是 250ms 合并写盘，这里再加一层内存层防抖）。

### 3.6 目录过滤/排序在每次 build 都重算
`files_page._filtered(state.items)` 每次 rebuild 都过滤 + 排序；大目录（2000 项）+ 滚动时
会频繁触发。建议把「过滤结果」存到 `FilesState`，只在 items/排序/筛选变化时重算。

---

## 4. P2：规范与可维护性

### 4.1 颜色字面量散落
`Color(0xFFD92D4B)`、`Color(0xFF0EA5E9)`、`Color(0xFF0B7A63)`、`0xFFFFF1F3` 等在 10+ 文件重复出现。
建议全部收进 `core/theme/tokens.dart`（`OlTokens.danger`、`sky600` 已存在，但 `dangerDeep`、
`okDeep`、警示底色等仍是散落字面量）。

### 4.2 字号缺少语义 token
8 / 8.5 / 9 / 9.5 / 10 / 10.5 / 11 / 11.5 / 12 / 12.5 / 17 共 11 档硬编码。
建议定义 `OlText.micro(8.5)`、`OlText.caption(9.5)`、`OlText.body(11)`、`OlText.title(17)`，
统一改一次即可全站生效，也避免以后调字号改漏。

### 4.3 `settings_sections.dart` 仍 691 行
6 个分区挤在一个 part。建议再拆 `sections/servers.dart`、`sections/download.dart`、
`sections/transfer_playback.dart`、`sections/appearance_about.dart`。

### 4.4 长 build 方法
`files_page._buildDesktop`、`servers_page._buildDesktop`、`server_form` 的表单 build 均超过
150 行，嵌套 6~8 层。建议把「标题栏 / 搜索筛选行 / 详情面板」抽成独立 widget，
既能缩短方法体，也能让每个区块独立重建（减少整页 rebuild）。

---

## 5. 已验证无问题的项

| 检查项 | 结果 |
|---|---|
| `first!` / `last!` / `[0]!` 强解包 | 无 |
| `as` 强转 | 2 处（`api.list` / `api.search`），上游均判过类型 |
| `print` 调试残留 | 无（统一 `debugPrint`） |
| 空 `catch` | 8 处，均为清理/回退路径且有注释 |
| Timer / Controller / Subscription 释放 | 全部在 `dispose` 中取消（`_ticker`、`_watchdog`、`_debounce`、`_errorSub`、`_player`） |
| `match!` 依赖「上面必 throw」 | 已改为 `match?.group(3)`（防御） |
| 凭据落盘 | 只进系统安全存储，`prefs.json` 无明文 |
| 路径穿越 | 下载路径逐级 `safePathSegment`（`..`、保留名、结尾点/空格、超长） |
| 401 语义 | 文件页操作 → 登出；下载任务 → 只标失败（签名过期不等于会话失效） |
| 单实例 | 文件锁 + UDP 唤醒，端口占用不再误判 |

---

## 6. 修复进度

| 项 | 状态 | 版本 | 说明 |
|---|---|---|---|
| P0 内联错误条 | ✅ 已修 | v1.0.42 | 保留旧列表时错误可见 + 重试 |
| P1-3.5 落盘合并 | ✅ 已修 | v1.0.44 | `_persist` 400ms 合并；dispose 立即 flush |
| P1-3.4 派生列表 | ⏭️ 评估不改 | — | getter 开销在微秒级，改计数反而引入一致性风险 |
| P1-3.6 过滤缓存 | ⏭️ 评估不改 | — | `_filtered` 无筛选时直接返回原列表，2000 项约 0.1ms |
| P1-3.3 扫描节流 | ✅ 已修 | v1.0.44 | 目录间 40ms + 翻页 80ms，提成常量 |
| P1-3.1 大文件拆分 | ✅ 已修 | v1.0.45 / 46 / 48 | 传输页 1227→254、服务器页 978→517、设置分区 639→4×150 |
| P1-3.2 启动并行 | ✅ 已修 | v1.0.44 | `me()` + `publicSettings()` 并行，错误语义分开 |
| P2-4.1 颜色 token | ✅ 已修 | v1.0.47 | 新增 3 个 danger token，14 个文件替换 |
| P2-4.3 分区再拆 | ✅ 已修 | v1.0.48 | `settings_sections.dart` → 4 个 part |
| P2-4.2 字号 token | ⏭️ 不建议做 | — | 见下 |
| P2-4.4 长 build 方法 | ✅ 已修 | v1.0.49 | `_buildDesktop` 190→55 行，抽出四个面板组件 |

### 关于字号 token（P2-4.2）—— 建议放弃

原建议是定义 `OlText.caption/body/title` 之类的语义字号并全量替换（约 200 处）。
实际核对后认为**收益低于风险**：

1. 字号在业务代码里几乎总是与 `fontWeight` / `color` 组合出现，
   `TextStyle(fontSize: 10.5, fontWeight: .w700, color: p.ink3)` 换成
   `OlText.meta.copyWith(color: p.ink3)` 反而更长、更绕。
2. 现有字号是 8/8.5/9/9.5/10/10.5/11/11.5/12/12.5/17 共 11 档，
   直接映射成 `xs/sm/md` 这类命名无法表达语义，只会把"魔法数字"换成"魔法缩写"。
3. `ol_controls.dart` 里的字号都走 `_mobileFont()` 做响应式缩放，本来就不该 token 化。

**替代方案**：若确实要统一，应该先**收敛档位**（把 11 档压到 5 档：8.5 / 9.5 / 11 / 12.5 / 17），
这属于视觉设计决策，需要你先确认视觉上能接受，再改一次字号值，比引入 token 更有效。

### 仍需跟进

- 返回卡顿：v1.0.44 加了 `RepaintBoundary`，**待实机验证**；若仍卡，说明单帧构建成本过高，
  下一步要拆分区 widget 并减少阴影层数（需先确认具体卡在哪一帧）。
- 字号档位收敛（11 → 5 档）属视觉决策，需产品确认后再动。
