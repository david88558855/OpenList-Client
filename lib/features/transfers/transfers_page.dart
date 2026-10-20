import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/models/api_types.dart';
import '../../core/models/transfer_task.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/file_widgets.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';
import '../../core/widgets/workspace_nav.dart';
import '../files/file_actions.dart';
import '../settings/download_dir.dart';
import 'transfers_controller.dart';

/// W3（Windows 传输中心）/ A3（Android 传输 Tab）。
///
/// 布局：队列侧栏 204 → 主区（速度卡 / 四个指标 / 任务列表）→ 设置面板 250。
/// 上传、下载、离线任务共用一套语义；暂停 / 继续 / 重试 / 限速都在这里。
class TransfersPage extends ConsumerStatefulWidget {
  const TransfersPage({super.key});

  @override
  ConsumerState<TransfersPage> createState() => _TransfersPageState();
}

enum _Filter { active, all, download, upload, offline, done, failed }

class _TransfersPageState extends ConsumerState<TransfersPage> {
  _Filter _filter = _Filter.active;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(transfersProvider.notifier).loadServerTasks();
    });
  }

  List<TransferTask> _visible(TransfersState state) {
    switch (_filter) {
      case _Filter.active:
        // v2.6：「进行中」只放真正的在途任务。已完成 / 失败的一律归到各自分组，
        // 之前这里返回 state.tasks（全部），导致传输完成后仍赖在「进行中」列表里。
        return state.tasks
            .where((e) => e.status != TransferStatus.done && e.status != TransferStatus.failed)
            .toList();
      case _Filter.all:
        return state.tasks;
      case _Filter.download:
        return state.tasks.where((e) => e.kind == TransferKind.download).toList();
      case _Filter.upload:
        return state.tasks.where((e) => e.kind == TransferKind.upload).toList();
      case _Filter.offline:
        return state.serverTasks.map(_fromServer).toList();
      case _Filter.done:
        return state.done;
      case _Filter.failed:
        return state.failed;
    }
  }

  TransferTask _fromServer(ServerTask task) => TransferTask(
        id: 'srv-${task.id}',
        serverId: '',
        serverLabel: '离线下载',
        kind: TransferKind.download,
        name: task.name,
        remotePath: '',
        localPath: '',
        total: task.totalBytes,
        done: task.doneBytes,
        status: TransferStatus.running,
        error: task.error,
      );

  @override
  Widget build(BuildContext context) {
    if (context.isNarrow) return _buildMobile(context);
    return _buildDesktop(context);
  }

  // ------------------------------------------------------------------ W3 桌面
  Widget _buildDesktop(BuildContext context) {
    final p = context.ol;
    final state = ref.watch(transfersProvider);
    final tasks = _visible(state);
    return AppFrame(
      navIndex: 1,
      handleBack: true,
      child: Row(
        children: [
          _QueueSidebar(filter: _filter, onFilter: (f) => setState(() => _filter = f)),
          Expanded(
            child: ColoredBox(
              color: p.surfaceAlt,
              child: Column(
                children: [
                  _TopBar(onNew: () => offlineDownload(context, ref)),
                  Expanded(
                    // v1.0.30：整页改 sliver 体系。原来任务列表是
                    // SingleChildScrollView + Column + for 循环，会把所有任务行
                    // 一次性 build（2000 个任务 = 2000 个进度监听），大目录下载时卡死。
                    // 现在任务行走 SliverList，按需构建。
                    child: CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                          sliver: SliverToBoxAdapter(child: _SpeedCard(state: state)),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverToBoxAdapter(child: _StatTiles(state: state, visible: tasks.length)),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          sliver: _TaskListSliver(
                            tasks: tasks,
                            filter: _filter,
                            onFilter: (f) => setState(() => _filter = f),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 250, child: _TransferSettings()),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- A3 移动端
  Widget _buildMobile(BuildContext context) {
    final p = context.ol;
    final state = ref.watch(transfersProvider);
    final visible = _visible(state);
    return AppFrame(
      navIndex: 1,
      handleBack: true,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              // v1.0.14：Android 也给显式返回（之前只能靠底部 tab 或系统返回）。
              padding: const EdgeInsets.fromLTRB(10, 8, OlGap.pageMobile, 8),
              child: Row(
                children: [
                  OlIconButton(icon: 'chev-l', size: 34, iconSize: 18, onTap: () => goBackOrFiles(context)),
                  const SizedBox(width: 2),
                  Text('传输', style: TextStyle(fontSize: 18, letterSpacing: -0.4, fontWeight: FontWeight.w800, color: p.ink)),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: OlGap.pageMobile),
              child: _SpeedCard(state: state, compact: true),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(OlGap.pageMobile, 12, OlGap.pageMobile, 0),
              child: Row(
                children: [
                  Expanded(
                    child: OlSeg<_Filter>(
                      items: const [
                        OlSegItem(_Filter.active, '进行中'),
                        OlSegItem(_Filter.done, '已完成'),
                        OlSegItem(_Filter.failed, '失败'),
                      ],
                      value: (_filter == _Filter.done || _filter == _Filter.failed) ? _filter : _Filter.active,
                      onChanged: (f) => setState(() => _filter = f),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OlGhostButton(
                    label: state.pausedGlobally ? '全部继续' : '全部暂停',
                    icon: state.pausedGlobally ? 'play' : 'pause',
                    height: 28,
                    fontSize: 10,
                    onTap: () {
                      final notifier = ref.read(transfersProvider.notifier);
                      if (state.pausedGlobally) {
                        notifier.resumeAll();
                      } else {
                        notifier.pauseAll();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          if (visible.isEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 240,
                // v2.6：完成的任务落到「已完成」，进行中为空时提示去哪找。
                child: _EmptyTransfers(
                  icon: switch (_filter) {
                    _Filter.failed => 'alert',
                    _Filter.done => 'check',
                    _ => 'arrow-down',
                  },
                  iconColor: _filter == _Filter.failed ? OlTokens.danger : null,
                  title: switch (_filter) {
                    _Filter.active => '没有进行中的任务',
                    _Filter.done => '还没有已完成的任务',
                    _Filter.failed => '没有失败的任务',
                    _ => '没有传输任务',
                  },
                  subtitle: switch (_filter) {
                    _Filter.active => '完成或失败的任务会移到对应分组',
                    _Filter.done => '下载或上传成功后出现在这里',
                    _Filter.failed => '传输失败时会出现在这里，可重试',
                    _ => '下载或上传文件后，这里会显示实时进度',
                  },
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: OlGap.pageMobile),
                  child: _TaskRow(task: visible[index], dense: true),
                ),
                childCount: visible.length,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 104)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 左侧队列
// ---------------------------------------------------------------------------
class _QueueSidebar extends ConsumerWidget {
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;
  const _QueueSidebar({required this.filter, required this.onFilter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final state = ref.watch(transfersProvider);
    final down = state.active.where((e) => e.kind == TransferKind.download).length;
    final up = state.active.where((e) => e.kind == TransferKind.upload).length;
    final doneBytes = state.done.fold<int>(0, (sum, e) => sum + e.total);

    return Container(
      width: 204,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(right: BorderSide(color: p.line2)),
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(9, 4, 9, 0),
              children: [
                // v1.0.17：工作区导航共用同一份组件（条目/顺序/badge 与其它页一致），
                // 下面是传输页独有的队列筛选。
                const WorkspaceNav(active: 'transfers'),
                const OlSectionLabel('队列'),
                _NavRow(
                  icon: 'layers',
                  label: '进行中',
                  badge: state.pendingCount,
                  active: filter == _Filter.active,
                  onTap: () => onFilter(_Filter.active),
                ),
                _NavRow(
                  icon: 'download',
                  label: '正在下载',
                  badge: down,
                  active: filter == _Filter.download,
                  onTap: () => onFilter(_Filter.download),
                ),
                _NavRow(
                  icon: 'upload',
                  label: '正在上传',
                  badge: up,
                  active: filter == _Filter.upload,
                  onTap: () => onFilter(_Filter.upload),
                ),
                _NavRow(
                  icon: 'cloud-dl',
                  label: '离线下载',
                  badge: state.serverTasks.length,
                  active: filter == _Filter.offline,
                  onTap: () => onFilter(_Filter.offline),
                ),
                _NavRow(
                  icon: 'check',
                  label: '已完成',
                  badge: state.done.length,
                  active: filter == _Filter.done,
                  onTap: () => onFilter(_Filter.done),
                ),
                _NavRow(
                  icon: 'alert',
                  label: '失败',
                  badge: state.failed.length,
                  danger: true,
                  active: filter == _Filter.failed,
                  onTap: () => onFilter(_Filter.failed),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(9, 8, 9, 12),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
            decoration: BoxDecoration(gradient: OlTokens.deepPanel, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('今日流量', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9DB4C8))),
                    const Spacer(),
                    const Text('不限速', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF5EEAD4))),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  formatBytes(doneBytes),
                  style: const TextStyle(fontSize: 20, height: 1.1, letterSpacing: -0.5, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text('下载 ${formatSpeed(state.downSpeed)}', style: const TextStyle(fontSize: 9, color: Color(0xFF8FA8BD))),
                    const Spacer(),
                    Text('上传 ${formatSpeed(state.upSpeed)}', style: const TextStyle(fontSize: 9, color: Color(0xFF8FA8BD))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final String icon;
  final String label;
  final int badge;
  final bool active;
  final bool danger;
  final VoidCallback? onTap;

  const _NavRow({
    required this.icon,
    required this.label,
    this.badge = 0,
    this.active = false,
    this.danger = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final fg = danger ? const Color(0xFFC2415A) : (active ? p.navOn : p.nav);
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 31,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: active ? p.navOnBg : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                OlIcon(icon, size: 15, color: danger ? const Color(0xFFE06B82) : (active ? OlTokens.sky600 : p.navIcon)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
                  ),
                ),
                if (badge > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: active ? p.card : p.navBadgeBg,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text('$badge', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: p.ink4)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 顶部条 / 速度卡 / 指标
// ---------------------------------------------------------------------------
class _TopBar extends ConsumerWidget {
  final VoidCallback onNew;
  const _TopBar({required this.onNew});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final state = ref.watch(transfersProvider);
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        border: Border(bottom: BorderSide(color: p.hairline)),
      ),
      child: Row(
        children: [
          // v1.0.14：传输是独立页面，顶部给显式返回。
          OlIconButton(icon: 'chev-l', size: 30, iconSize: 17, tooltip: '返回', onTap: () => goBackOrFiles(context)),
          const SizedBox(width: 6),
          Text('传输中心', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.ink)),
          const SizedBox(width: 4),
          OlIcon('chev-r', size: 12, color: p.ink4),
          const SizedBox(width: 4),
          Text('全部任务', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: p.ink3)),
          const Spacer(),
          OlIconButton(
            icon: state.pausedGlobally ? 'play' : 'pause',
            tooltip: state.pausedGlobally ? '全部继续' : '全部暂停',
            squared: true,
            onTap: () {
              final notifier = ref.read(transfersProvider.notifier);
              if (state.pausedGlobally) {
                notifier.resumeAll();
              } else {
                notifier.pauseAll();
              }
            },
          ),
          const SizedBox(width: 8),
          OlGhostButton(label: '新建任务', icon: 'plus', height: 30, onTap: onNew),
        ],
      ),
    );
  }
}

class _SpeedCard extends StatelessWidget {
  final TransfersState state;
  final bool compact;
  const _SpeedCard({required this.state, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final total = state.downSpeed + state.upSpeed;
    final mb = total / (1024 * 1024);
    return Container(
      height: compact ? 118 : 132,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0C1E2E), Color(0xFF0E2C40), Color(0xFF0F3A46)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        children: [
          Positioned(right: -30, top: -70, child: _glow(220, const Color(0x382DD4BF))),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CURRENT THROUGHPUT',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: Color(0xFF8FB2C6)),
                        ),
                        const SizedBox(height: 7),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              mb >= 10 ? mb.toStringAsFixed(0) : mb.toStringAsFixed(1),
                              style: TextStyle(
                                fontSize: compact ? 28 : 31,
                                height: 1,
                                letterSpacing: -1,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(left: 4, bottom: 3),
                              child: Text('MB/s ↓', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9EBBCE))),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _SpeedMeta(label: '上传', value: formatSpeed(state.upSpeed)),
                            const SizedBox(width: 12),
                            _SpeedMeta(label: '活动任务', value: '${state.active.length}'),
                            const SizedBox(width: 12),
                            _SpeedMeta(label: '并发', value: '${state.concurrency}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    decoration: BoxDecoration(
                      color: const Color(0x17FFFFFF),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: const Color(0x24FFFFFF)),
                    ),
                    child: const Center(
                      child: Text('全局不限速', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFBFE6F5))),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              SizedBox(
                height: compact ? 36 : 44,
                child: CustomPaint(
                  painter: _SparkPainter(value: total <= 0 ? 0.12 : (mb / 8).clamp(0.15, 1.0)),
                  size: Size.infinite,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _glow(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [color, color.withAlpha(0)])),
      );
}

class _SpeedMeta extends StatelessWidget {
  final String label;
  final String value;
  const _SpeedMeta({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$label ', style: const TextStyle(fontSize: 9, color: Color(0xFF8FA8BD))),
        Text(value, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFCFE6F3))),
      ],
    );
  }
}

class _SparkPainter extends CustomPainter {
  final double value;
  _SparkPainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..moveTo(0, size.height * 0.8);
    const steps = 12;
    for (var i = 1; i <= steps; i++) {
      final x = size.width * i / steps;
      final wave = (i.isEven ? 0.35 : 0.65) * value;
      final y = size.height * (0.75 - wave * 0.6);
      final cx = size.width * (i - 0.5) / steps;
      path.quadraticBezierTo(cx, y, x, size.height * (0.72 - wave * 0.5));
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x6138BDF8), Color(0x0038BDF8)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0xFF7DD3FC),
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter oldDelegate) => oldDelegate.value != value;
}

class _StatTiles extends StatelessWidget {
  final TransfersState state;
  final int visible;
  const _StatTiles({required this.state, required this.visible});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final doneBytes = state.done.fold<int>(0, (sum, e) => sum + e.total);
    return Row(
      children: [
        Expanded(child: _Tile(icon: 'arrow-down', label: '下载速度', value: formatSpeed(state.downSpeed), palette: p)),
        const SizedBox(width: 8),
        Expanded(child: _Tile(icon: 'arrow-up', label: '上传速度', value: formatSpeed(state.upSpeed), palette: p)),
        const SizedBox(width: 8),
        Expanded(child: _Tile(icon: 'zap', label: '队列', value: '$visible 项', palette: p)),
        const SizedBox(width: 8),
        Expanded(child: _Tile(icon: 'clock', label: '今日完成', value: formatBytes(doneBytes), palette: p)),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final String icon;
  final String label;
  final String value;
  final OlPalette palette;
  const _Tile({required this.icon, required this.label, required this.value, required this.palette});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: p.line2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OlIcon(icon, size: 11, color: p.ink4),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: p.ink4)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, letterSpacing: -0.3, fontWeight: FontWeight.w800, color: p.ink),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 任务列表（sliver 版：按需构建任务行，v1.0.30）
// ---------------------------------------------------------------------------
class _TaskListSliver extends StatelessWidget {
  final List<TransferTask> tasks;
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;

  const _TaskListSliver({required this.tasks, required this.filter, required this.onFilter});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return DecoratedSliver(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.line2),
      ),
      sliver: SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(child: _TaskListHeader(tasks: tasks, filter: filter, onFilter: onFilter)),
          if (tasks.isEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 160,
                child: _EmptyTransfers(
                  icon: switch (filter) {
                    _Filter.failed => 'alert',
                    _Filter.done => 'check',
                    _ => 'arrow-down',
                  },
                  iconColor: filter == _Filter.failed ? OlTokens.danger : null,
                  title: switch (filter) {
                    _Filter.failed => '没有失败的任务',
                    _Filter.done => '还没有已完成的任务',
                    _Filter.offline => '没有离线下载任务',
                    _ => '没有进行中的任务',
                  },
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _TaskRow(task: tasks[index]),
                childCount: tasks.length,
              ),
            ),
        ],
      ),
    );
  }
}

/// 卡片头：标题 + 全部/下载/上传 分段。
class _TaskListHeader extends StatelessWidget {
  final List<TransferTask> tasks;
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;

  const _TaskListHeader({required this.tasks, required this.filter, required this.onFilter});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    // v2.6：标题跟随筛选走。之前固定写「进行中」，切到已完成/失败仍是这个标题。
    final title = switch (filter) {
      _Filter.done => '已完成',
      _Filter.failed => '失败',
      _Filter.offline => '离线下载',
      _Filter.download => '正在下载',
      _Filter.upload => '正在上传',
      _ => '进行中',
    };
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line2))),
      child: Row(
        children: [
          Text(title, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: p.ink2)),
          const Spacer(),
          OlSeg<_Filter>(
            items: [
              OlSegItem(_Filter.all, '全部 ${tasks.length}'),
              OlSegItem(_Filter.download, '下载'),
              OlSegItem(_Filter.upload, '上传'),
            ],
            value: (filter == _Filter.upload || filter == _Filter.download) ? filter : _Filter.all,
            onChanged: onFilter,
            height: 21,
          ),
        ],
      ),
    );
  }
}

class _TaskRow extends ConsumerWidget {
  final TransferTask task;
  final bool dense;
  const _TaskRow({required this.task, this.dense = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final notifier = ref.read(transfersProvider.notifier);
    final ratio = task.total <= 0 ? 0.0 : (task.done / task.total).clamp(0.0, 1.0);
    final failed = task.status == TransferStatus.failed;
    final running = task.status == TransferStatus.running;
    final done = task.status == TransferStatus.done;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 0 : 12, vertical: 9),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.divider))),
      child: Row(
        children: [
          FileGlyph(name: task.name, size: 30, radius: 8, iconSize: 15),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.ink),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        failed ? '连接失败' : task.serverLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: failed ? FontWeight.w700 : FontWeight.w500,
                          color: failed ? const Color(0xFFD92D4B) : p.ink4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(formatSpeed(task.speed), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: p.ink2)),
                    const SizedBox(width: 7),
                    Text('${formatBytes(task.done)} / ${formatBytes(task.total)}', style: TextStyle(fontSize: 9, color: p.ink4)),
                  ],
                ),
                const SizedBox(height: 5),
                OlProgress(value: ratio, height: 3),
              ],
            ),
          ),
          SizedBox(
            width: 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  done ? '完成' : '${(ratio * 100).round()}%',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: failed ? const Color(0xFFD92D4B) : p.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  done || task.speed <= 0 ? '' : '剩余 ${formatCountdown(((task.total - task.done) / task.speed).round())}',
                  style: TextStyle(fontSize: 9, color: p.ink4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          // 离线下载任务由服务端执行，本地暂停/重试无意义（v2.2 审计）。
          if (task.id.startsWith('srv-'))
            SizedBox(
              width: 24,
              height: 24,
              child: Center(child: OlIcon('cloud-dl', size: 12, color: p.ink4)),
            )
          else if (failed)
            OlGhostButton(label: '重试', height: 22, fontSize: 9, onTap: () => notifier.retry(task.id))
          else if (running)
            OlIconButton(icon: 'pause', size: 24, iconSize: 12, tooltip: '暂停', onTap: () => notifier.pause(task.id))
          else if (task.status == TransferStatus.paused)
            OlIconButton(icon: 'play', size: 24, iconSize: 12, tooltip: '继续', onTap: () => notifier.resume(task.id))
          else
            OlIconButton(icon: 'x', size: 24, iconSize: 12, tooltip: '移除', onTap: () => notifier.remove(task.id)),
        ],
      ),
    );
  }
}

class _EmptyTransfers extends StatelessWidget {
  final String? title;
  final String? subtitle;

  /// v1.0.30：图标跟随筛选。之前固定用向下箭头，切到「失败」时
  /// 也显示下载箭头，看起来像功能坏了（截图里「没有失败的任务」配了个 ↓）。
  final String icon;
  final Color? iconColor;

  const _EmptyTransfers({
    this.title,
    this.subtitle,
    this.icon = 'arrow-down',
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OlIcon(icon, size: 24, color: iconColor ?? p.ink4),
          const SizedBox(height: 8),
          Text(
            title ?? '没有传输任务',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.ink3),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle ?? '下载或上传文件后，这里会显示实时进度',
            style: TextStyle(fontSize: 9.5, color: p.ink4),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 右侧设置面板（W3 · tright 250）
// ---------------------------------------------------------------------------
class _TransferSettings extends ConsumerWidget {
  const _TransferSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final settings = ref.watch(appSettingsProvider);
    final profile = ref.watch(sessionProvider).profile;
    final notifier = ref.watch(appSettingsProvider.notifier);

    return Container(
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        border: Border(left: BorderSide(color: p.line2)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        children: [
          Row(
            children: [
              Text('传输设置', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1, color: p.ink4)),
              const Spacer(),
              OlIcon('settings', size: 13, color: p.ink4),
            ],
          ),
          const SizedBox(height: 8),
          _LimitRow(
            label: '下载限速',
            value: settings.downLimitKbps,
            unit: 'KB/s',
            onTap: () => _editLimit(
              context,
              title: '下载限速',
              current: settings.downLimitKbps,
              onDone: notifier.setDownLimit,
            ),
          ),
          _LimitRow(
            label: '上传限速',
            value: settings.upLimitKbps,
            unit: 'KB/s',
            onTap: () => _editLimit(
              context,
              title: '上传限速',
              current: settings.upLimitKbps,
              onDone: notifier.setUpLimit,
            ),
          ),
          _LimitRow(
            label: '并发任务数',
            value: settings.concurrency,
            unit: '个',
            onTap: () => _editLimit(
              context,
              title: '并发任务数',
              current: settings.concurrency,
              onDone: notifier.setConcurrency,
              max: 8,
            ),
          ),
          const SizedBox(height: 12),
          Text('时段限速', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: p.ink4)),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final day in const ['一', '二', '三', '四', '五', '六', '日'])
                Container(
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    gradient: day == '日' ? null : OlTokens.gradientBrand,
                    color: day == '日' ? p.surface : null,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      day,
                      style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.w700, color: day == '日' ? p.ink4 : Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text('工作日 09:00–18:00 限速 2 MB/s，其余时段不限速。', style: TextStyle(fontSize: 9, height: 1.6, color: p.ink4)),
          const SizedBox(height: 12),
          Text('完成后', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: p.ink4)),
          _SwitchRow(label: '任务完成通知', value: settings.trayNotify, onChanged: notifier.setTrayNotify),
          _SwitchRow(
            label: '后台保持传输',
            value: settings.backgroundTransfer,
            onChanged: notifier.setBackgroundTransfer,
          ),
          const SizedBox(height: 12),
          Text('下载位置', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: p.ink4)),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => showDownloadDirDialog(context, ref),
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: p.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile == null
                        ? '未连接服务器'
                        : (ref.read(serverStoreProvider).readDownloadDir(profile.id) ?? '默认目录（按实例隔离）'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: p.ink2),
                  ),
                  const SizedBox(height: 4),
                  Text('点击更改', style: TextStyle(fontSize: 8.5, color: p.ink4)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OlGhostButton(
                  label: '暂停全部',
                  height: 28,
                  fontSize: 10,
                  onTap: () => ref.read(transfersProvider.notifier).pauseAll(),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OlSoftButton(
                  label: '打开目录',
                  height: 28,
                  onTap: () async {
                    if (profile == null || !Platform.isWindows) return;
                    final dir = await resolveDownloadDir(ref, profile);
                    try {
                      await Process.run('explorer', [dir]);
                    } catch (_) {
                      if (context.mounted) olToast(context, '无法打开目录：$dir', error: true);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editLimit(
    BuildContext context, {
    required String title,
    required int current,
    required ValueChanged<int> onDone,
    int max = 1024 * 1024,
  }) async {
    final controller = TextEditingController(text: '$current');
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '0 表示不限速'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('取消')),
          TextButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim()) ?? 0;
              Navigator.of(dialogContext).pop(parsed.clamp(0, max).toInt());
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) onDone(value);
  }
}

class _LimitRow extends StatelessWidget {
  final String label;
  final int value;
  final String unit;
  final VoidCallback onTap;
  const _LimitRow({required this.label, required this.value, required this.unit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line2))),
        child: Row(
          children: [
            Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink2)),
            const Spacer(),
            Container(
              height: 26,
              constraints: const BoxConstraints(minWidth: 58),
              padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: p.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$value', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: p.ink)),
                  const SizedBox(width: 3),
                  Text(unit, style: TextStyle(fontSize: 8.5, color: p.ink4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line2))),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink2)),
          const Spacer(),
          OlSwitch(value: value, small: true, onChanged: onChanged),
        ],
      ),
    );
  }
}
