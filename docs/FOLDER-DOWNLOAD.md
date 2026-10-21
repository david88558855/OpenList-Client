# 方案：文件夹递归下载（含子目录全部文件）

> 状态：**已实现**（v1.0.31，方案 A）。实现位置：
> - `TransferTask.localSubdir` 保存相对子目录（旧数据缺该字段时按空串处理）；
> - `TransfersController.enqueueDownloadInto()` 负责建目录 + 入队；
> - `file_actions.dart` 的 `_scanFolders()` BFS 遍历 + `_FolderScanDialog` 进度弹窗，
>   `downloadItems()` 对「含文件夹」的批量下载走扫描分支。
>
> 下方保留原始方案与验收标准，作为实现依据与回归清单。

## 1. 目标与非目标

**目标**

- 批量操作里选中的文件夹（可混合文件），一次点击下载该目录下**所有层级**的文件。
- 本地保留与远端一致的目录结构：`下载目录/OpenList/<文件夹名>/<子目录>/<文件>`。
- 入队前给出可感知的进度（扫描中 / 已入队 N 个），支持中途取消。
- 单个子目录失败不阻断整体，结束后汇总「成功 X / 跳过 Y / 失败 Z」。

**非目标**

- 不做服务端打包（`/api/fs/archive` 视服务端实现而定，见第 7 节备选）。
- 不做断点续传之外的秒传/校验和比对。
- 不处理符号链接与循环引用（OpenList 的 `/api/fs/list` 返回的是逻辑路径，不存在硬链接环）。

## 2. 现状与限制点

| 位置 | 现状 |
|---|---|
| `file_actions.dart` → `downloadItems()` | 只对 `!isDir` 的项调用 `downloadItem`，文件夹直接跳过并 toast |
| `transfers_controller.dart` → `enqueueDownload(item, currentDir)` | `if (item.isDir) return '暂不支持整目录下载';`；本地路径固定为 `下载目录/<文件名>`，**不保留子目录** |
| `openlist_api.dart` → `list(parent, page, perPage, refresh)` | 已支持分页列目录，可直接用于递归遍历 |

结论：需要在**任务模型**里补一个「本地相对子目录」，并在**动作层**加一个遍历器。

## 3. 方案

### 3.1 任务模型与入队接口

`TransferTask` 增加（或用现有 `localPath` 承载，推荐新增字段便于展示）：

```dart
final String? localSubdir;   // 相对下载根的子目录，例如 "电影/2024"
```

新增入队方法，保留原方法作为薄封装（`localSubdir = ''`）：

```dart
Future<String?> enqueueDownloadInto(
  FileItem item, {
  required String remotePath,   // 完整远端路径，item.parent + name
  required String localSubdir,  // 相对下载根的子目录
});
```

本地路径 = `下载目录 + sep + safePathSegment(每级 localSubdir) + sep + safePathSegment(item.name)`；
入队前 `Directory(...).create(recursive: true)`。**每一级都要过 `safePathSegment`**，
防止远端目录名带 `..`、结尾点或 Windows 保留名。

### 3.2 遍历器（BFS，串行 list）

放在 `file_actions.dart`（或新建 `folder_download.dart`）：

```
scan(rootPath):
  queue = [ (remote: rootPath, subdir: '') ]
  visited = {}
  files = []          // (FileItem, localSubdir)
  while queue 非空 and 未取消:
    (remote, subdir) = queue.removeFirst()
    if remote in visited: continue          // 防重复（服务端返回异常时兜底）
    visited.add(remote)
    for page in 1..:
      items = api.list(parent: remote, page: page, perPage: 100)
      目录项 → queue.add((joinPath(remote, name), '$subdir/${name}'))
      文件项 → files.add((item, subdir))
      if items.length < perPage: break
    if files.length > maxFiles: 中断并提示
    if depth(subdir) > maxDepth: 跳过并计数
```

约束（硬编码为常量，避免服务端异常导致无限翻页/无限递归）：

| 限制 | 值 | 说明 |
|---|---|---|
| 最大文件数 | 2000 | 超出提示「文件过多，请分批」 |
| 最大深度 | 24 | 超出目录记为跳过 |
| 每页条数 | 100 | 与文件页一致 |
| 相邻两个 list 请求 | 串行 + 80ms 间隔 | 避免把服务端打满 |

### 3.3 UI 与进度

批量条点击「下载」后：

1. 若选中项全部是文件 → 直接走现有 `downloadItems`（保持轻量，不弹窗）。
2. 若含文件夹 → 弹一个可取消的进度面板（复用 `olConfirm` 风格或底部 sheet）：
   - 阶段一「正在扫描目录…已发现 N 个文件」；
   - 阶段二「正在入队 N/M」；
   - 右上角「取消」→ 置中止标记，已入队的任务保留（用户可见并可控）。
3. 结束 toast：`已加入 N 个文件（跳过 M 个空目录/超限目录）`；有失败时按 `error: true` 显示。

### 3.4 空目录

默认**创建空目录**（`localSubdir` 对应的每个目录都 `create`），保持结构与远端一致；
若某目录在本轮没有任何文件，也创建一个空目录（可通过设置项关闭，默认开）。

### 3.5 冲突与重复

- 同一远程文件重复入队：沿用现有 `_resolveLocalPath` 的「同 remotePath 复用原任务」逻辑，
  不产生重复任务。
- 本地已有同名文件：沿用现有策略（存在则顺延 `name (2).ext`），文件夹场景下因为保留了
  子目录，天然减少冲突。

### 3.6 失败处理

| 场景 | 处理 |
|---|---|
| 某个子目录 `list` 失败（403/404/超时） | 记录该目录，继续其它目录；结束时汇总 |
| 单个文件入队失败（sign 过期等） | 记录，继续；结束时汇总 |
| 用户取消 | 停止扫描与入队，已入队任务保留 |
| 断网 | 首次 `list` 失败即终止并提示，不做半截入队（避免用户看到一堆 failed 任务） |

## 4. 需要改动的文件

| 文件 | 改动 |
|---|---|
| `lib/core/models/api_types.dart` | `TransferTask` 增加 `localSubdir`（可空，向后兼容旧持久化数据） |
| `lib/features/transfers/transfers_controller.dart` | 新增 `enqueueDownloadInto`；`_resolveLocalPath` 支持子目录；`_persist/restore` 兼容新字段 |
| `lib/features/files/file_actions.dart` | `downloadItems` 分流：纯文件走原路径，含目录走扫描 + 入队；新增进度面板 |
| `lib/features/files/parts/files_mobile.dart` | 批量条无需改（已调用 `downloadItems`） |
| `lib/features/transfers/transfers_page.dart` | 任务行显示相对子目录（可选，作为副标题） |
| `docs/PROJECT.md` / `README.md` | 更新「已知限制」里「文件夹暂不支持」的描述 |

## 5. 分步实施（每步可单独验证）

1. **模型 + 入队**：`localSubdir` 字段 + `enqueueDownloadInto`，先用「手动传子目录」的单测式入口验证落盘路径正确（本地跑一次下载到嵌套目录）。
2. **遍历器**：实现 `scanFolder`，只打印结果不弹窗，用一个大目录验证条数/深度上限与取消。
3. **接 UI**：批量条 → 进度面板 → toast 汇总。
4. **收尾**：任务行副标题、文档更新、CHANGELOG。

## 6. 验收标准

- 选中一个含 3 层子目录、约 50 个文件的文件夹 → 下载完成后本地目录结构与远端逐级一致，
  文件数相等，无 0 字节文件。
- 选中「2 个文件夹 + 3 个文件」→ 文件夹按结构落盘，3 个文件落在下载根。
- 扫描达到 2000 个文件 → 提示并停止，已入队部分可正常下载。
- 扫描过程中点取消 → 不再新增任务，已完成任务可继续。
- 某个子目录无权限（403）→ 其余目录正常，结束时提示跳过数量。
- 重启应用 → 队列中的子目录任务能从已写入字节续传，路径不变。

## 7. 备选方案与取舍

| 方案 | 优点 | 缺点 | 结论 |
|---|---|---|---|
| **A. 客户端递归遍历 + 逐文件入队**（本方案） | 复用现有单文件下载、续传、限速；服务端无额外要求 | 大目录会产生很多请求与任务行 | **采用** |
| B. 服务端打包 zip 后下载 | 一次请求、快 | 依赖服务端 `/api/fs/archive` 等接口，多数部署未开启；大目录打包耗 CPU；无法续传 | 作为「高级选项」待服务端支持后再评估 |
| C. 只下载顶层文件，子目录跳过 | 实现最省事 | 不满足「含子目录全部文件」的需求 | 否 |

## 8. 风险

- **任务行爆炸**：2000 个文件 = 2000 条任务，`transfers_page` 是全量渲染的 `ListView`，
  需要改为 `ListView.builder` 或分组折叠，否则卡顿。→ 实施第 3 步前先确认列表性能。
- **服务端限流**：串行 + 80ms 间隔是经验值，若服务端更严格需退避（429 已有 2s 重试）。
- **路径长度**：Windows 260 字符上限；`safePathSegment` 已截断单段，但深层嵌套仍可能超限，
  需在入队时检测总长度并跳过（记录到汇总）。
