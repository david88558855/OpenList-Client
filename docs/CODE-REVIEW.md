# 代码审查报告（v1.0.21）

审查范围：`lib/` 全部 Dart 源码（16 个模块、约 15.9k 行）。
方法：三轮人工 + 脚本复核（未使用符号扫描、跨文件私有引用检查、括号/字符串结构校验），
抽查点包含并发、异常路径、跨平台差异与数据完整性。

分级：**P0 数据/功能必现错误** / **P1 特定条件下出错或体验明显受损** / **P2 健壮性/整洁度**。

> **修复进度**
> - v1.0.21：第 1~5 条（prefs 原子替换与并发、下载取消、搜索清空/异常）。
> - v1.0.22：第 6~13、15~20、26 条（续传校验、播放器四条、下载路径、凭据自愈、选目录、搜索条数、延迟持久化）。
> - v1.0.23：第 14、21、27、28、29、30 条（搜索光标顺序、4xx 错误文案、暂停语义、分页去重、SP 分支类型、授权闭环）。
> - 仅剩 #31/#32 两项结构性建议（超大文件拆分、控件命名统一），不影响功能。

---

## 一、P0（高）—— 已修复

| # | 位置 | 问题 | 原因 | 影响 / 处理 |
|---|---|---|---|---|
| 1 | `core/storage/prefs.dart` `_flushNow` | 先 `delete` 再 `rename`，不是原子替换 | 两步之间存在窗口；rename 失败（被杀毒软件占用/跨卷）时目标已删、新文件未就位 | 断电或异常退出会**丢失全部配置**（服务器列表、收藏、浏览位置）。已改为「旧文件改名 `.bak` → tmp 就位 → 失败回滚 `.bak`」 |
| 2 | `core/storage/prefs.dart` `_schedule/_flushNow` | 定时器回调与 `flush()` 可能并发写同一个 `.tmp` | `_dirty=false` 在 IO 前、`force` 绕过检查、无互斥 | 两路 JSON 交错 → 损坏文件 → 下次启动走「损坏」分支清空数据。已用 `_flushing/_pending` 串行化 |
| 3 | `core/api/openlist_api.dart` `downloadToFile` | 取消下载用 `break` 静默收尾并返回已收字节 | 无取消信号，上层按正常返回处理 | 半截文件被标为**已完成**（静默截断）。已改为抛 `ApiException(-1, '传输已取消')`，上层在 paused 分支不会覆盖状态 |
| 4 | `features/search/search_page.dart` `_onChanged` | 清空关键词不回滚请求序号 | 只清列表，不 `++_seq`、不复位 `_loading` | 在途请求返回后覆盖空状态：搜索框空着却列出一堆结果。已修 |
| 5 | `features/search/search_page.dart` `_run` | 只 `on ApiException`，无通用兜底 | Socket/Timeout/解析异常不在此列，且 `_run` 的 Future 无人 await | `_loading` 永久为 true，页面再也搜不动。已加通用 `catch` 与「未连接」提示 |

## 二、P0（高）—— 已修复（v1.0.22）

| # | 位置 | 问题 | 原因 | 影响 |
|---|---|---|---|---|
| 6 | `core/api/openlist_api.dart` `downloadToFile` | 断点续传无任何校验：不读 `Content-Range`、不比对远端大小/ETag，结尾不断言 `received == total` | 只用「本地长度 > 0 且返回 206」判定续传 | 远端文件被替换时会把新数据追加到旧字节后（静默损坏）；本地长度已等于远端大小时服务端返回 416，被当成错误，`retry()` 永远失败 |
| 7 | `features/media/player_page.dart:78` | 用「文件名相同」兜底匹配当前播放项 | `item.name == _currentName` 跨目录可能命中同名文件 | 取到错误文件的 `sign` → 403 / 播放到错误内容；播放列表高亮也对不上 |
| 8 | `features/media/player_page.dart:65-100` | `_boot()` 无请求序号 | 连续点击列表两条会启动两个 `_boot`，`open` 完成顺序不定 | 画面与标题可能来自不同文件；`_loading` 被先到的响应提前置 false |
| 9 | `features/media/player_page.dart:89-93` | 播放失败无 UI 反馈 | 未订阅 `player.stream.error`，`catch` 接不到异步解码/网络错误 | 黑屏 + `00:00 / 00:00`，无错误文案、无重试入口 |

## 三、P1（中）

| # | 位置 | 问题 | 影响 |
|---|---|---|---|
| 10 | `features/media/player_page.dart:149-169` | 切换视频时不保存上一个的进度（只有 `dispose` 才存，且 `_currentPath` 已变） | 播放列表内切换后，上一个视频的续播点丢失 |
| 11 | `features/media/player_page.dart:97-99` | 续播位置未按 duration 裁剪（存的是片尾位置） | 打开即播完，需手动拖回 |
| 12 | `features/media/player_page.dart:122-147` | `_attachSubtitle` 未 await、未做 mounted 保护、部分语句在 try 之外 | dispose 后 `ref.read` 抛异常；失败无人感知 |
| 13 | `features/media/player_page.dart:172-183` | 退出播放页不复位全屏 | 返回文件页后整个窗口仍是全屏 |
| 14 | `features/search/search_page.dart:126-135` | 键盘光标按 `_results` 顺序，渲染按「文件夹→文件」重排 | ↓ 高亮跳到视觉不相邻的行，Enter 打开的与看到的不一致；同名文件同时高亮 |
| 15 | `features/search/search_page.dart:85-89` | 只取第一页（默认 50 条），无分页/加载更多 | 命中多时结果被静默截断，计数误导 |
| 16 | `core/storage/download_paths.dart:17-20,61` | `safePathSegment` 只过滤 9 个字符，未处理 `..`、末尾点/空格、`CON/PRN/NUL`、长度 | 服务器名为 `..` 时下载目录逃出 `OpenList` 根；`mkdir` 失败或超出 260 字符 |
| 17 | `core/storage/download_paths.dart:66-78` | 回退目录丢掉「按实例隔离」 | 多服务器同名文件互相覆盖；设置页显示路径与实际不一致 |
| 18 | `features/settings/download_dir.dart:220-223` | 目录选择无 try/catch、不校验可写 | `PlatformException` 冒到未处理区；不可写路径被持久化后每次回退，UI 长期误导 |
| 19 | `core/storage/secure_store.dart:11-26` | 读写异常全部吞掉，不区分「不存在」与「底层损坏」 | keystore 失效时表现为反复被踢回登录页，且无法自愈（不会清理后重写） |
| 20 | `core/api/openlist_api.dart:364-369` | 先 `openWrite(FileMode.write)` 截断文件，再判断 `body == null` | 本可保留的本地文件被抹成 0 字节后任务失败 |
| 21 | `core/api/openlist_api.dart:45-51` | 4xx 只从 JSON body 取 message，且把 HTTP 状态码与业务码混用 | 反向代理返回 HTML 错误页时提示为空；`needsReauth` 等判断可能误触发 |

## 四、P2（低 / 整洁度）

| # | 位置 | 问题 | 处理 |
|---|---|---|---|
| 22 | `core/widgets/file_widgets.dart` | `OlMediaThumb`（122 行）、`OlUsageBar` 死代码（详情面板/用量卡删除后无人引用） | 已删除 |
| 23 | `app/app.dart` | `OlPageScaffold`、`OlHairline` 死代码 | 已删除 |
| 24 | `core/theme/tokens.dart` | `OlThemeContext` extension 死代码 | 已删除 |
| 25 | `core/format.dart` | `formatDateTime`、`segmentsOf` 死代码 | 已删除 |
| 26 | `core/providers.dart` `AppSettingsNotifier` | `rememberLatency` 只改内存，`toJson` 不写 `last_latency`，但构造时又读它 | 读取永远拿不到值 —— 建议要么持久化要么删掉读取分支 |
| 27 | `features/transfers/transfers_controller.dart` | `pauseAll/resumeAll` 不区分「全局暂停」与「用户手动暂停」 | 全部继续会把用户单独暂停的任务一起恢复 |
| 28 | `features/files/files_controller.dart` `loadMore` | 结果未去重 | 服务端分页不稳定时同一条目出现两次 |
| 29 | `core/storage/prefs.dart`（SP 分支） | `Map`/`null` 值被静默丢弃，`List` 一律字符串化 | Windows（JSON）与 Android（SharedPreferences）行为不一致 |
| 30 | `features/settings/download_dir.dart:207-219` | 授权流程不闭环（授权返回后不重试选择） | 重复点「选择目录」陷入同一弹窗 |
| 31 | 结构性 | `files_page.dart`(1748) / `settings_page.dart`(1208) / `transfers_page.dart`(1143) / `servers_page.dart`(950) 单文件过大 | 建议按「页面壳 / 列表 / 面板 / 表单」拆分；本轮不改，避免大范围回归 |
| 32 | 命名 | `_TinyButton` / `_DarkChip` / `_RoundBtn` / `_CircleBtn` 同类控件四处不同名 | 建议后续统一为 `OlSmallButton` 等；不影响功能 |

---

## 五、三轮复核结论

- **第 1 轮（逻辑）** 共 21 条，去重后 18 条（播放器 7、搜索 4、存储 5、API 3、设置 2）。
- **第 2 轮（整洁度）** 共 7 处死代码（已全部删除，净减约 220 行）+ 1 处重复实现（四页侧栏已在上版收敛为 `WorkspaceNav`）+ 4 处命名不统一 + 4 个超大文件。
- **第 3 轮（复核）** 修正了 2 条误判（`_TinyButton` 的 `onTapDown` 与 `_CacheIndex` 均在正常使用）；合并重复项 3 条；补漏 2 条（#20 先截断后判空、#21 错误消息来源）。
- 本轮已修复 **5 条 P0**（数据丢失/功能卡死），其余按上表留待排期。

## 六、后续建议（v1.0.22 已完成前四项）

1. ~~续传校验~~ —— 已在 v1.0.22 落地（Content-Range + 完整性断言 + 416 提示）。
2. ~~播放器四连~~ —— 已加 `_bootSeq`、订阅 `error` 流、按完整路径匹配 sign、切换保存进度。
3. ~~下载路径~~ —— `safePathSegment` 统一规则，传输侧复用同一实现。
4. ~~凭据自愈~~ —— 读失败清理坏条目并重试写入。
5. 剩余建议：把 `files_page.dart`(1748) / `settings_page.dart`(1208) / `transfers_page.dart`(1143)
   按「页面壳 / 列表 / 面板 / 表单」拆分，并统一 `_TinyButton` / `_DarkChip` / `_RoundBtn` 这类同类控件命名。
   这两项是纯结构整理，改动面大且不影响功能，建议单独排期。
