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
import '../../core/widgets/ol_icon.dart';
import '../files/file_actions.dart';
import '../settings/download_dir.dart';
import 'transfers_controller.dart';

/// W3（Windows 传输中心）/ A3（Android 传输 Tab）。
///
/// 上传 / 下载 / 离线下载三合一；顶部实时速度，右侧全局限速与完成策略。
class TransfersPage extends ConsumerStatefulWidget {
  const TransfersPage({super.key});

  @override
  ConsumerState<TransfersPage> createState() => _TransfersPageState();
}

enum _Filter { all, download, upload, offline, done, failed }

class _TransfersPageState extends ConsumerState<TransfersPage> {
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(transfersProvider.notifier).loadServerTasks();
    });
  }

  List<TransferTask> _visible(TransfersState s) {
    switch (_filter) {
      case _Filter.all:
        return s.tasks;
      case _Filter.download:
        return s.tasks.where((e) => e.kind == TransferKind.download).toList();
      case _Filter.upload:
        return s.tasks.where((e) => e.kind == TransferKind.upload).toList();
      case _Filter.offline:
        return s.serverTasks.map(_fromServer).toList();
      case _Filter.done:
        return s.done;
      case _Filter.failed:
        return s.failed;
    }
  }

  TransferTask _fromServer(ServerTask t) => TransferTask(
        id: 'srv-${t.id}',
        serverId: '',
        serverLabel: '离线下载',
        kind: TransferKind.download,
        name: t.name,
        remotePath: '',
        localPath: '',
        total: t.totalBytes,
        done: t.doneBytes,
        status: TransferStatus.running,
        error: t.error,
      );

  @override
  Widget build(BuildContext context) {
    if (context.isNarrow) return _buildMobile(context);
    return _buildDesktop(context);
  }

  // ------------------------------------------------------------------
  // W3 · Windows
  // ------------------------------------------------------------------
  Widget _buildDesktop(BuildContext context) {
    final p = context.ol;
    final state = ref.watch(transfersProvider);
    return AppFrame(
      navIndex: 1,
      child: Row(
        children: [
          _QueueSidebar(filter: _filter, onFilter: (f) => setState(() => _filter = f)),
          Expanded(
            child: Container(
              color: p.isDark ? const Color(0xFF0B1622) : const Color(0xFFFBFDFF),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopBar(onNew: () => offlineDownload(context, ref)),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(OlGap.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SpeedCard(state: state),
                          const SizedBox(height: OlGap.sm),
                          _StatTiles(state: state),
                          const SizedBox(height: OlGap.sm),
                          _TaskList(
                            tasks: _visible(state),
                            filter: _filter,
                            onFilter: (f) => setState(() => _filter = f),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: 250, child: _TransferSettings()),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // A3 · Android
  // ------------------------------------------------------------------
  Widget _buildMobile(BuildContext context) {
    final state = ref.watch(transfersProvider);
    final visible = _visible(state);
    return AppFrame(
      navIndex: 1,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _MobileHead()),
          SliverToBoxAdapter(child: _SpeedCard(state: state, dark: true)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(OlGap.pageMobile, OlGap.sm, OlGap.pageMobile, 0),
              child: Row(
                children: [
                  Expanded(
                    child: OlSeg<_Filter>(
                      items: const [
                        OlSegItem(_Filter.all, '进行中'),
                        OlSegItem(_Filter.done, '已完成'),
                        OlSegItem(_Filter.failed, '失败'),
                      ],
                      value: _filter == _Filter.done || _Filter.failed ? _filter : _Filter.all,
                      onChanged: (f) => setState(() => _filter = f),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OlGhostButton(
                    label: '全部暂停',
                    icon: 'pause',
                    height: 28,
                    onTap: () => ref.read(transfersProvider.notifier).pauseAll(),
                  ),
                ],
              ),
            ),
          ),
          if (visible.isEmpty)
            const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: 64), child: _EmptyTransfers()))
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: OlGap.pageMobile),
                  child: _MobileTaskRow(task: visible[index]),
                ),
                childCount: visible.length,
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(OlGap.pageMobile, OlGap.md, OlGap.pageMobile, 0),
              child: _MobileToggles(),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    );
  }
}

class _MobileHead extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Padding(
      padding: const EdgeInsets.fromLTRB(OlGap.pageMobile, 14, OlGap.pageMobile, 10),
      child: Text('传输', style: OlText.display.copyWith(color: p.ink)),
    );
  }
}

// ---------------------------------------------------------------------------
// W3 左侧队列
// ---------------------------------------------------------------------------
class _QueueSidebar extends ConsumerWidget {
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;

  const _QueueSidebar({required this.filter, required this.onFilter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final s = ref.watch(transfersProvider);
    final down = s.active.where((e) => e.kind == TransferKind.download).length;
    final up = s.active.where((e) => e.kind == TransferKind.upload).length;
    final doneBytes = s.done.fold<int>(0, (sum, e) => sum + e.total);

    return Container(
      width: 204,
      color: p.surface,
      decoration: BoxDecoration(border: Border(right: BorderSide(color: p.line2))),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(9, 10, 9, 0),
              children: [
                const OlSectionLabel('队列'),
                _QueueRow(icon: 'download', label: '正在下载', count: down, active: filter == _Filter.download, onTap: () => onFilter(_Filter.download)),
                _QueueRow(icon: 'upload', label: '正在上传', count: up, active: filter == _Filter.upload, onTap: () => onFilter(_Filter.upload)),
                _QueueRow(icon: 'cloud-dl', label: '离线下载', count: s.serverTasks.length, active: filter == _Filter.offline, onTap: () => onFilter(_Filter.offline)),
                _QueueRow(icon: 'check', label: '已完成', count: s.done.length, active: filter == _Filter.done, onTap: () => onFilter(_Filter.done)),
                _QueueRow(icon: 'alert', label: '失败', count: s.failed.length, active: filter == _Filter.failed, onTap: () => onFilter(_Filter.failed)),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(9, 8, 9, 12),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              gradient: OlTokens.deepPanel,
              borderRadius: BorderRadius.circular(OlTokens.r3),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('今日流量', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9DB4C8))),
                    ),
                    const Text('不限速', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF5EEAD4))),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  formatBytes(doneBytes),
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: Colors.white),
                ),
                const SizedBox(height: 7),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('下载 ${formatBytes(s.downSpeed)}', style: const TextStyle(fontSize: 9, color: Color(0xFF8FA8BD))),
                    Text('上传 ${formatBytes(s.upSpeed)}', style: const TextStyle(fontSize: 9, color: Color(0xFF8FA8BD))),
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

class _QueueRow extends StatelessWidget {
  final String icon;
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  const _QueueRow({
    required this.icon,
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            height: 31,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: active ? p.navOnBg : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                OlIcon(icon, size: 15, color: active ? OlTokens.sky600 : p.navIcon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w650, color: active ? p.navOn : p.nav),
                  ),
                ),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: active ? p.card : p.navBadgeBg,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text('$count', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: p.ink3)),
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
// 顶栏
// ---------------------------------------------------------------------------
class _TopBar extends ConsumerWidget {
  final VoidCallback onNew;
  const _TopBar({required this.onNew});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.hairline))),
      child: Row(
        children: [
          Text('传输中心', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: p.ink)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(color: p.chipBg, borderRadius: BorderRadius.circular(OlTokens.rPill)),
            child: Text('全部任务', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: p.ink3)),
          ),
          const Spacer(),
          OlGhostButton(label: '筛选任务', icon: 'filter', height: 28, onTap: () {}),
          const SizedBox(width: 8),
          OlPrimaryButton(label: '新建任务', icon: 'plus', height: 28, onTap: onNew),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 速度卡 + 统计块
// ---------------------------------------------------------------------------
class _SpeedCard extends ConsumerWidget {
  final TransfersState state;
  final bool dark;

  const _SpeedCard({required this.state, this.dark = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final p = context.ol;
    final isDark = dark || p.isDark;
    return Container(
      height: 132,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                begin: Alignment(-0.8, -1),
                end: Alignment(0.9, 1),
                colors: [Color(0xFF0C1E2E), Color(0xFF0E2C40), Color(0xFF0F3A46)],
              )
            : const LinearGradient(
                begin: Alignment(-0.8, -1),
                end: Alignment(0.9, 1),
                colors: [Color(0xFF0C1E2E), Color(0xFF0E2C40), Color(0xFF0F3A46)],
              ),
        borderRadius: BorderRadius.circular(OlTokens.rCard),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [Color(0x382DD4BF), Color(0x002DD4BF)]),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'CURRENT THROUGHPUT',
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.4, color: Color(0xFF8FB2C6)),
                    ),
                  ),
                  Text(
                    settings.downLimitKbps == 0 && settings.upLimitKbps == 0
                        ? '全局不限速'
                        : '限速 ${settings.downLimitKbps} KB/s',
                    style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFF8FA8BD)),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    (state.downSpeed / 1024 / 1024).toStringAsFixed(1),
                    style: const TextStyle(fontSize: 31, height: 1, fontWeight: FontWeight.w800, letterSpacing: -1, color: Colors.white),
                  ),
                  const SizedBox(width: 4),
                  const Text('MB/s ↓', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF9EBBCE))),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('上传 ${formatSpeed(state.upSpeed)}', style: const TextStyle(fontSize: 9.5, color: Color(0xFF8FA8BD))),
                  const SizedBox(width: 12),
                  Text('活动任务 ${state.active.length}', style: const TextStyle(fontSize: 9.5, color: Color(0xFF8FA8BD))),
                  const SizedBox(width: 12),
                  Text('剩余 ${formatCountdown(_eta(state))}', style: const TextStyle(fontSize: 9.5, color: Color(0xFF8FA8BD))),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _eta(TransfersState s) {
    final speed = s.downSpeed + s.upSpeed;
    if (speed <= 0) return 0;
    var remain = 0;
    for (final t in s.active) {
      remain += (t.total - t.done).clamp(0, t.total);
    }
    return remain ~/ speed;
  }
}

class _StatTiles extends ConsumerWidget {
  final TransfersState state;
  const _StatTiles({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final doneBytes = state.done.fold<int>(0, (sum, e) => sum + e.total);
    return Row(
      children: [
        Expanded(child: _Tile(label: '下载速度', value: formatSpeed(state.downSpeed), icon: 'download', card: p.card, line: p.line, ink: p.ink, ink3: p.ink3)),
        const SizedBox(width: 8),
        Expanded(child: _Tile(label: '上传速度', value: formatSpeed(state.upSpeed), icon: 'upload', card: p.card, line: p.line, ink: p.ink, ink3: p.ink3)),
        const SizedBox(width: 8),
        Expanded(child: _Tile(label: '队列', value: '${state.pendingCount}', icon: 'inbox', card: p.card, line: p.line, ink: p.ink, ink3: p.ink3)),
        const SizedBox(width: 8),
        Expanded(child: _Tile(label: '今日完成', value: formatBytes(doneBytes), icon: 'check', card: p.card, line: p.line, ink: p.ink, ink3: p.ink3)),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final String value;
  final String icon;
  final Color card;
  final Color line;
  final Color ink;
  final Color ink3;

  const _Tile({
    required this.label,
    required this.value,
    required this.icon,
    required this.card,
    required this.line,
    required this.ink,
    required this.ink3,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OlIcon(icon, size: 11, color: ink3),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: ink3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: ink),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 任务列表
// ---------------------------------------------------------------------------
class _TaskList extends ConsumerWidget {
  final List<TransferTask> tasks;
  final _Filter filter;
  final ValueChanged<_Filter> onFilter;

  const _TaskList({required this.tasks, required this.filter, required this.onFilter});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final s = ref.watch(transfersProvider);
    final down = s.tasks.where((e) => e.kind == TransferKind.download).length;
    final up = s.tasks.where((e) => e.kind == TransferKind.upload).length;

    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(OlTokens.r3),
        border: Border.all(color: p.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line2))),
            child: Row(
              children: [
                Text('进行中', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: p.ink2)),
                const Spacer(),
                OlSeg<_Filter>(
                  height: 21,
                  items: [
                    OlSegItem(_Filter.all, '全部 ${s.tasks.length}'),
                    OlSegItem(_Filter.download, '下载 $down'),
                    OlSegItem(_Filter.upload, '上传 $up'),
                  ],
                  value: filter,
                  onChanged: onFilter,
                ),
              ],
            ),
          ),
          if (tasks.isEmpty)
            const Padding(padding: EdgeInsets.all(28), child: _EmptyTransfers())
          else
            for (final t in tasks) _TaskRow(task: t),
        ],
      ),
    );
  }
}

class _TaskRow extends ConsumerWidget {
  final TransferTask task;
  const _TaskRow({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final failed = task.status == TransferStatus.failed;
    final done = task.status == TransferStatus.done;
    final running = task.status == TransferStatus.running;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.divider))),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: failed
                  ? const Color(0xFFFFF1F3)
                  : (done ? const Color(0xFFE7FBF5) : (p.isDark ? const Color(0xFF101F31) : const Color(0xFFF2F8FC))),
              borderRadius: BorderRadius.circular(OlTokens.r4),
            ),
            child: Center(
              child: OlIcon(
                task.kind == TransferKind.upload ? 'upload' : (failed ? 'alert' : 'download'),
                size: 14,
                color: failed ? const Color(0xFFD92D4B) : (done ? const Color(0xFF0B7A63) : OlTokens.sky600),
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w750, color: p.ink),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        failed
                            ? (task.error ?? '传输失败')
                            : '${task.serverLabel} → ${task.kind == TransferKind.upload ? '远端' : '本地'} · ${formatSpeed(task.speed)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w550,
                          color: failed ? const Color(0xFFD92D4B) : p.ink4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      '${formatBytes(task.done)} / ${formatBytes(task.total)}',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: p.ink2),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                OlProgress(value: task.progress, height: 3),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${(task.progress * 100).round()}%',
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: p.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  failed ? '失败' : (done ? '完成' : (running ? '剩余 ${formatCountdown(_eta(task))}' : '已暂停')),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: p.ink4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (failed)
                OlIconButton(
                  icon: 'rotate',
                  size: 26,
                  iconSize: 14,
                  tooltip: '重试',
                  onTap: () => ref.read(transfersProvider.notifier).retry(task.id),
                )
              else if (running)
                OlIconButton(
                  icon: 'pause',
                  size: 26,
                  iconSize: 14,
                  tooltip: '暂停',
                  onTap: () => ref.read(transfersProvider.notifier).pause(task.id),
                )
              else if (!done)
                OlIconButton(
                  icon: 'play',
                  size: 26,
                  iconSize: 14,
                  tooltip: '继续',
                  onTap: () => ref.read(transfersProvider.notifier).resume(task.id),
                ),
              OlIconButton(
                icon: 'x',
                size: 26,
                iconSize: 14,
                tooltip: '移除',
                onTap: () => ref.read(transfersProvider.notifier).remove(task.id),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _eta(TransferTask t) {
    if (t.speed <= 0) return 0;
    return ((t.total - t.done).clamp(0, t.total) / t.speed).round();
  }
}

class _MobileTaskRow extends ConsumerWidget {
  final TransferTask task;
  const _MobileTaskRow({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final failed = task.status == TransferStatus.failed;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.divider))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w750, color: p.ink),
                ),
              ),
              Text('${(task.progress * 100).round()}%', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: p.ink)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            failed
                ? (task.error ?? '连接超时 · 已重试')
                : '${task.serverLabel} → 本地 · ${formatSpeed(task.speed)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w550, color: failed ? const Color(0xFFD92D4B) : p.ink4),
          ),
          const SizedBox(height: 7),
          OlProgress(value: task.progress, height: 3),
          const SizedBox(height: 5),
          Row(
            children: [
              Text('${formatBytes(task.done)} / ${formatBytes(task.total)}', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: p.ink4)),
              const Spacer(),
              if (!failed)
                Text('剩余 ${formatCountdown(_eta(task))}', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: p.ink4)),
              if (failed)
                OlGhostButton(
                  label: '重试',
                  icon: 'rotate',
                  height: 26,
                  onTap: () => ref.read(transfersProvider.notifier).retry(task.id),
                ),
            ],
          ),
        ],
      ),
    );
  }

  int _eta(TransferTask t) {
    if (t.speed <= 0) return 0;
    return ((t.total - t.done).clamp(0, t.total) / t.speed).round();
  }
}

class _EmptyTransfers extends StatelessWidget {
  const _EmptyTransfers();

  @override
  Widget build(BuildContext context) {
    return OlEmptyState(
      icon: 'inbox',
      title: '暂无传输任务',
      subtitle: '从文件列表下载，或把文件拖进目录即可开始上传。',
    );
  }
}

class _MobileToggles extends ConsumerWidget {
  const _MobileToggles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final settings = ref.watch(appSettingsProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(OlTokens.r3),
        border: Border.all(color: p.line),
      ),
      child: Column(
        children: [
          _ToggleRow(
            label: '仅在 Wi-Fi 下传输',
            icon: 'wifi',
            value: settings.wifiOnly,
            onChanged: (v) => ref.read(appSettingsProvider.notifier).setWifiOnly(v),
          ),
          _ToggleRow(
            label: '后台保持传输',
            sub: '前台服务',
            icon: 'server',
            value: settings.backgroundTransfer,
            onChanged: (v) => ref.read(appSettingsProvider.notifier).setBackgroundTransfer(v),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// W3 右侧传输设置
// ---------------------------------------------------------------------------
class _TransferSettings extends ConsumerStatefulWidget {
  const _TransferSettings();

  @override
  ConsumerState<_TransferSettings> createState() => _TransferSettingsState();
}

class _TransferSettingsState extends ConsumerState<_TransferSettings> {
  late final TextEditingController _down;
  late final TextEditingController _up;

  @override
  void initState() {
    super.initState();
    final s = ref.read(appSettingsProvider);
    _down = TextEditingController(text: '${s.downLimitKbps}');
    _up = TextEditingController(text: '${s.upLimitKbps}');
  }

  @override
  void dispose() {
    _down.dispose();
    _up.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final settings = ref.watch(appSettingsProvider);
    final state = ref.watch(transfersProvider);

    return Container(
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        border: Border(left: BorderSide(color: p.line2)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _GroupTitle('传输设置'),
          _NumRow(
            label: '下载限速',
            unit: 'KB/s',
            controller: _down,
            onSubmitted: (v) => ref.read(appSettingsProvider.notifier).setDownLimit(int.tryParse(v) ?? 0),
          ),
          _NumRow(
            label: '上传限速',
            unit: 'KB/s',
            controller: _up,
            onSubmitted: (v) => ref.read(appSettingsProvider.notifier).setUpLimit(int.tryParse(v) ?? 0),
          ),
          _StepRow(
            label: '并发任务数',
            value: settings.concurrency,
            onChanged: (v) => ref.read(transfersProvider.notifier).setConcurrency(v),
          ),
          _StepRow(
            label: '分片线程',
            value: 8,
            onChanged: (_) {},
          ),
          const SizedBox(height: 10),
          _GroupTitle('时段限速'),
          const _WeekRow(),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '工作日 09:00–18:00 限速 2 MB/s，其余时段不限速。',
              style: TextStyle(fontSize: 9, height: 1.6, color: p.ink4),
            ),
          ),
          const SizedBox(height: 14),
          _GroupTitle('完成后'),
          _ToggleRow(
            label: '任务完成通知',
            icon: 'bell',
            value: settings.trayNotify,
            onChanged: (v) => ref.read(appSettingsProvider.notifier).setTrayNotify(v),
          ),
          _ToggleRow(label: '全部完成后休眠', icon: 'moon', value: false, onChanged: (_) {}),
          const SizedBox(height: 14),
          _GroupTitle('下载位置'),
          const SizedBox(height: 6),
          const DownloadDirLine(),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OlGhostButton(
                  label: '暂停全部',
                  icon: 'pause',
                  height: 28,
                  onTap: () => ref.read(transfersProvider.notifier).pauseAll(),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OlGhostButton(
                  label: '继续全部',
                  icon: 'play',
                  height: 28,
                  onTap: () => ref.read(transfersProvider.notifier).resumeAll(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          OlGhostButton(
            label: '清理已完成',
            icon: 'trash',
            height: 28,
            onTap: () => ref.read(transfersProvider.notifier).clearFinished(),
          ),
          if (state.error != null) ...[
            const SizedBox(height: 10),
            Text(state.error!, style: const TextStyle(fontSize: 10, height: 1.5, color: Color(0xFFD92D4B))),
          ],
        ],
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  final String text;
  const _GroupTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.9, color: context.ol.th),
      ),
    );
  }
}

class _NumRow extends StatelessWidget {
  final String label;
  final String unit;
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  const _NumRow({required this.label, required this.unit, required this.controller, required this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink2))),
          SizedBox(
            width: 78,
            height: 26,
            child: TextField(
              controller: controller,
              textAlign: TextAlign.end,
              keyboardType: TextInputType.number,
              onSubmitted: onSubmitted,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: p.ink),
              decoration: InputDecoration(
                suffixText: unit,
                suffixStyle: TextStyle(fontSize: 8.5, color: p.ink4),
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
                filled: true,
                fillColor: p.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: p.fieldBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: p.fieldBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFF7DD3FC)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _StepRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink2))),
          _RoundButton(icon: 'minus', onTap: value > 1 ? () => onChanged(value - 1) : null, card: p.card, line: p.line, ink: p.ink2),
          SizedBox(
            width: 30,
            child: Center(child: Text('$value', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: p.ink))),
          ),
          _RoundButton(icon: 'plus', onTap: value < 16 ? () => onChanged(value + 1) : null, card: p.card, line: p.line, ink: p.ink2),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final String icon;
  final VoidCallback? onTap;
  final Color card;
  final Color line;
  final Color ink;

  const _RoundButton({required this.icon, required this.onTap, required this.card, required this.line, required this.ink});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: line),
        ),
        child: Center(child: OlIcon(icon, size: 11, color: onTap == null ? const Color(0xFFB4C3D1) : ink)),
      ),
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow();

  static const days = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Row(
      children: [
        for (var i = 0; i < days.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                gradient: i < 5 ? OlTokens.gradientPrimary : null,
                color: i < 5 ? null : (p.isDark ? const Color(0xFF14243A) : const Color(0xFFEEF5FA)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Text(
                  days[i],
                  style: TextStyle(
                    fontSize: 7.5,
                    fontWeight: FontWeight.w700,
                    color: i < 5 ? Colors.white : p.ink4,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String? sub;
  final String icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({required this.label, required this.icon, required this.value, required this.onChanged, this.sub});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 23,
            height: 23,
            decoration: BoxDecoration(
              color: p.isDark ? const Color(0xFF14243A) : const Color(0xFFF2F8FC),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(child: OlIcon(icon, size: 12, color: p.ink3)),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: p.ink)),
                if (sub != null)
                  Text(sub!, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: p.ink4)),
              ],
            ),
          ),
          OlSwitch(value: value, onChanged: onChanged, small: true),
        ],
      ),
    );
  }
}
