import 'dart:async';
import 'dart:math' as math;

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
import '../files/file_actions.dart';
import 'transfers_controller.dart';

class TransfersPage extends ConsumerStatefulWidget {
  const TransfersPage({super.key});

  @override
  ConsumerState<TransfersPage> createState() => _TransfersPageState();
}

class _TransfersPageState extends ConsumerState<TransfersPage> {
  final List<double> _history = [];
  Timer? _timer;
  String _tab = 'all';

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final state = ref.read(transfersProvider);
      setState(() {
        _history.add(state.downSpeed + state.upSpeed);
        if (_history.length > 56) _history.removeAt(0);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<TransferTask> _filtered(TransfersState state) {
    switch (_tab) {
      case 'download':
        return state.tasks.where((e) => e.kind == TransferKind.download).toList();
      case 'upload':
        return state.tasks.where((e) => e.kind == TransferKind.upload).toList();
      case 'done':
        return state.done;
      case 'failed':
        return state.failed;
      default:
        return state.tasks.where((e) => e.status != TransferStatus.done).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 900;
    final body = narrow ? _buildMobile(context) : _buildDesktop(context);
    return AppFrame(navIndex: 1, child: body);
  }

  Widget _buildDesktop(BuildContext context) {
    final p = context.ol;
    final state = ref.watch(transfersProvider);
    final tasks = _filtered(state);

    return Row(
      children: [
        _QueueSidebar(tab: _tab, onTab: (v) => setState(() => _tab = v)),
        Expanded(
          child: Container(
            color: p.isDark ? const Color(0xFF0B1622) : const Color(0xFFFBFDFF),
            child: Column(
              children: [
                Container(
                  height: 50,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.hairline))),
                  child: Row(
                    children: [
                      Text('传输中心', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.ink)),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 3), child: OlIcon('chev-r', size: 12, color: Color(0xFFB2C1CF))),
                      Text('全部任务', style: TextStyle(fontSize: 11.5, color: p.ink3)),
                      const Spacer(),
                      OlIconButton(
                        icon: state.pausedGlobally ? 'play' : 'pause',
                        squared: true,
                        tooltip: state.pausedGlobally ? '继续全部' : '暂停全部',
                        onTap: () async {
                          if (state.pausedGlobally) {
                            await ref.read(transfersProvider.notifier).resumeAll();
                          } else {
                            await ref.read(transfersProvider.notifier).pauseAll();
                          }
                        },
                      ),
                      const SizedBox(width: 6),
                      OlGhostButton(
                        label: '新建任务',
                        icon: 'plus',
                        onTap: () async {
                          final size = MediaQuery.sizeOf(context);
                          final position = Offset(size.width - 210, 54);
                          await showOlMenu(context, position: position, items: [
                            OlMenuItem('上传文件', 'upload', () => pickAndUpload(context, ref)),
                            OlMenuItem('离线下载', 'cloud-dl', () => offlineDownload(context, ref)),
                            OlMenuItem('打开下载目录', 'folder', () async {
                              final task = state.tasks.where((e) => e.kind == TransferKind.download).toList();
                              if (task.isEmpty) {
                                olToast(context, '还没有下载任务');
                              } else {
                                olToast(context, task.first.localPath);
                              }
                            }),
                          ]);
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                          child: Column(
                            children: [
                              _SpeedCard(state: state, history: _history),
                              const SizedBox(height: 10),
                              _StatTiles(state: state),
                              const SizedBox(height: 10),
                              _TaskList(tasks: tasks, tab: _tab, onTab: (v) => setState(() => _tab = v)),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        width: 250,
                        decoration: BoxDecoration(
                          color: p.surfaceAlt,
                          border: Border(left: BorderSide(color: p.line2)),
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const _PanelTitle('限速与并发'),
                              _LimitRow(
                                label: '下载限速',
                                value: ref.watch(appSettingsProvider).downLimitKbps,
                                onChanged: (v) => ref.read(appSettingsProvider.notifier).setDownLimit(v),
                              ),
                              _LimitRow(
                                label: '上传限速',
                                value: ref.watch(appSettingsProvider).upLimitKbps,
                                onChanged: (v) => ref.read(appSettingsProvider.notifier).setUpLimit(v),
                              ),
                              const SizedBox(height: 6),
                              Text('并发任务', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: p.ink2)),
                              const SizedBox(height: 6),
                              OlSeg<int>(
                                items: const [
                                  OlSegItem(1, '1'),
                                  OlSegItem(2, '2'),
                                  OlSegItem(4, '4'),
                                  OlSegItem(6, '6'),
                                ],
                                value: ref.watch(appSettingsProvider).concurrency,
                                onChanged: (v) {
                                  ref.read(appSettingsProvider.notifier).setConcurrency(v);
                                  ref.read(transfersProvider.notifier).setConcurrency(v);
                                },
                              ),
                              const SizedBox(height: 14),
                              const _PanelTitle('完成策略'),
                              const _CheckLine(label: '完成后保留在列表', checked: true),
                              _CheckLine(
                                label: '完成后通知（托盘 / 通知栏）',
                                checked: ref.watch(appSettingsProvider).trayNotify,
                                onChanged: (v) => ref.read(appSettingsProvider.notifier).setTrayNotify(v),
                              ),
                              const SizedBox(height: 14),
                              const _PanelTitle('离线下载'),
                              OlGhostButton(label: '刷新服务端任务', icon: 'refresh', onTap: () => ref.read(transfersProvider.notifier).loadServerTasks()),
                              const SizedBox(height: 8),
                              _ServerTaskList(tasks: state.serverTasks),
                              const SizedBox(height: 12),
                              OlDangerButton(label: '清除已完成 / 失败', icon: 'trash', onTap: () => ref.read(transfersProvider.notifier).clearFinished()),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobile(BuildContext context) {
    final p = context.ol;
    final state = ref.watch(transfersProvider);
    final settings = ref.watch(appSettingsProvider);
    final ongoing = state.tasks
        .where((e) =>
            e.status == TransferStatus.running ||
            e.status == TransferStatus.queued ||
            e.status == TransferStatus.paused ||
            e.status == TransferStatus.failed)
        .toList();
    final doneList = state.done;

    List<TransferTask> tasks;
    switch (_tab) {
      case 'done':
        tasks = doneList;
        break;
      case 'failed':
        tasks = state.failed;
        break;
      default:
        tasks = ongoing;
        break;
    }

    return Column(
      children: [
        SizedBox(
          height: 54,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Text('传输', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: p.ink)),
                const Spacer(),
                _CircleBtn(
                  icon: state.pausedGlobally ? 'play' : 'pause',
                  onTap: () async {
                    if (state.pausedGlobally) {
                      await ref.read(transfersProvider.notifier).resumeAll();
                    } else {
                      await ref.read(transfersProvider.notifier).pauseAll();
                    }
                  },
                ),
                const SizedBox(width: 8),
                _CircleBtn(
                  icon: 'more-v',
                  onTap: () async {
                    final size = MediaQuery.sizeOf(context);
                    final position = Offset(size.width - 38, 96);
                    await showOlMenu(context, position: position, items: [
                      OlMenuItem('上传文件', 'upload', () => pickAndUpload(context, ref)),
                      OlMenuItem('离线下载', 'cloud-dl', () => offlineDownload(context, ref)),
                      OlMenuItem('清除已完成', 'trash', () => ref.read(transfersProvider.notifier).clearFinished()),
                    ]);
                  },
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: _MobileSpeedCard(state: state),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
          child: Row(
            children: [
              OlChip(
                label: '进行中 ${ongoing.length}',
                selected: _tab == 'all',
                height: 26,
                onTap: () => setState(() => _tab = 'all'),
              ),
              const SizedBox(width: 6),
              OlChip(
                label: '已完成 ${doneList.length}',
                selected: _tab == 'done',
                height: 26,
                onTap: () => setState(() => _tab = 'done'),
              ),
              const SizedBox(width: 6),
              OlChip(
                label: '失败 ${state.failed.length}',
                selected: _tab == 'failed',
                height: 26,
                onTap: () => setState(() => _tab = 'failed'),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () async {
                  if (state.pausedGlobally) {
                    await ref.read(transfersProvider.notifier).resumeAll();
                  } else {
                    await ref.read(transfersProvider.notifier).pauseAll();
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      state.pausedGlobally ? '全部继续' : '全部暂停',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: p.ink4),
                    ),
                    const SizedBox(width: 3),
                    OlIcon('chev-r', size: 10, color: p.ink4),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: tasks.isEmpty
              ? OlEmptyState(
                  icon: 'arrow-down',
                  title: _tab == 'failed'
                      ? '没有失败的任务'
                      : (_tab == 'done' ? '还没有完成的任务' : '队列是空的'),
                  subtitle: '从文件页下载或在「新建任务」里上传，进度会实时显示在这里。',
                  action: OlPrimaryButton(label: '去文件页', icon: 'folder', onTap: () => context.go('/files')),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                  children: [
                    for (final t in tasks) _MobileTaskCard(task: t),
                    if (_tab == 'all' && doneList.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
                        child: Row(
                          children: [
                            Text('刚刚完成', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: p.ink4)),
                            const Spacer(),
                            GestureDetector(
                              onTap: () => setState(() => _tab = 'done'),
                              child: Text('全部', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: const Color(0xFF0A93C4))),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: p.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: p.line2),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 11),
                        child: Column(
                          children: [
                            for (int i = 0; i < doneList.length && i < 4; i++) ...[
                              if (i > 0)
                                Container(height: 1, color: p.line2),
                              SizedBox(
                                height: 38,
                                child: Row(
                                  children: [
                                    OlIcon('check', size: 14, color: const Color(0xFF0B7A63)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        doneList[i].name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: p.ink2),
                                      ),
                                    ),
                                    Text(
                                      '${formatBytes(doneList[i].total)} · ${_agoLabel(doneList[i].createdAt)}',
                                      style: TextStyle(fontSize: 8.5, color: p.ink4),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    if (_tab == 'all') ...[
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: p.card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: p.line2),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          children: [
                            SizedBox(
                              height: 42,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text('仅在 Wi-Fi 下传输', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink2)),
                                  ),
                                  OlSwitch(
                                    value: settings.wifiOnly,
                                    small: true,
                                    onChanged: (v) => ref.read(appSettingsProvider.notifier).setWifiOnly(v),
                                  ),
                                ],
                              ),
                            ),
                            Container(height: 1, color: p.line2),
                            SizedBox(
                              height: 42,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Text('后台保持传输', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink2)),
                                        const SizedBox(width: 6),
                                        Text('前台服务', style: TextStyle(fontSize: 8.5, color: p.ink4)),
                                      ],
                                    ),
                                  ),
                                  OlSwitch(
                                    value: settings.backgroundTransfer,
                                    small: true,
                                    onChanged: (v) => ref.read(appSettingsProvider.notifier).setBackgroundTransfer(v),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  static String _agoLabel(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inMinutes < 60) return '${d.inMinutes} 分钟前';
    if (d.inHours < 24) return '${d.inHours} 小时前';
    return '${d.inDays} 天前';
  }
}

class _QueueSidebar extends ConsumerWidget {
  final String tab;
  final ValueChanged<String> onTab;

  const _QueueSidebar({required this.tab, required this.onTab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final state = ref.watch(transfersProvider);
    return Container(
      width: 204,
      color: p.surface,
      padding: const EdgeInsets.fromLTRB(9, 4, 9, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OlSectionLabel('工作区'),
          _SideRow(icon: 'folder', label: '所有文件', onTap: () => context.go('/files')),
          _SideRow(icon: 'clock', label: '最近使用', onTap: () => context.push('/favorites?tab=recent')),
          _SideRow(icon: 'star', label: '收藏', onTap: () => context.push('/favorites')),
          _SideRow(icon: 'share', label: '我的分享', onTap: () => context.push('/favorites')),
          _SideRow(icon: 'arrow-down', label: '传输任务', badge: '${state.pendingCount}', active: true, onTap: () {}),
          const OlSectionLabel('队列'),
          _SideRow(icon: 'download', label: '正在下载', badge: '${state.tasks.where((e) => e.kind == TransferKind.download && e.status == TransferStatus.running).length}', active: tab == 'download', onTap: () => onTab('download')),
          _SideRow(icon: 'upload', label: '正在上传', badge: '${state.tasks.where((e) => e.kind == TransferKind.upload && e.status == TransferStatus.running).length}', active: tab == 'upload', onTap: () => onTab('upload')),
          _SideRow(icon: 'cloud-dl', label: '离线下载', onTap: () => ref.read(transfersProvider.notifier).loadServerTasks()),
          _SideRow(icon: 'check', label: '已完成', active: tab == 'done', onTap: () => onTab('done')),
          _SideRow(icon: 'alert', label: '失败', danger: state.failed.isNotEmpty, badge: state.failed.isEmpty ? null : '${state.failed.length}', active: tab == 'failed', onTap: () => onTab('failed')),
          const Spacer(),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            decoration: BoxDecoration(gradient: OlTokens.deepPanel, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Text('实时速率', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF9DB4C8))),
                    Spacer(),
                    Text('不限速', style: TextStyle(fontSize: 9, color: Color(0xFF8FA8BD))),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  formatSpeed(state.downSpeed + state.upSpeed),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: Colors.white),
                ),
                const SizedBox(height: 6),
                OlProgress(value: (state.downSpeed + state.upSpeed) / (20 * 1024 * 1024), height: 4, darkTrack: true),
                const SizedBox(height: 6),
                Text(
                  '↓ ${formatSpeed(state.downSpeed)}   ↑ ${formatSpeed(state.upSpeed)}',
                  style: const TextStyle(fontSize: 9, color: Color(0xFF8FA8BD)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SideRow extends StatelessWidget {
  final String icon;
  final String label;
  final String? badge;
  final bool active;
  final bool danger;
  final VoidCallback onTap;

  const _SideRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
    this.active = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 31,
        margin: const EdgeInsets.only(bottom: 1),
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(color: active ? p.navOnBg : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            OlIcon(icon, size: 15, color: active ? const Color(0xFF0EA5E9) : (danger ? const Color(0xFFE06B82) : p.navIcon)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? p.navOn : (danger ? const Color(0xFFC2415A) : p.nav)),
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: active ? p.card : p.navBadgeBg, borderRadius: BorderRadius.circular(5)),
                child: Text(badge!, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: p.ink3)),
              ),
          ],
        ),
      ),
    );
  }
}

class _SpeedCard extends StatelessWidget {
  final TransfersState state;
  final List<double> history;

  const _SpeedCard({required this.state, required this.history});

  @override
  Widget build(BuildContext context) {
    final speed = state.downSpeed;
    final active = state.active.length;
    final remainingBytes = state.tasks.where((e) => e.status != TransferStatus.done).fold<int>(0, (sum, e) => sum + math.max(0, e.total - e.done));
    final eta = (speed > 0 ? remainingBytes / speed : 0).round();

    return Container(
      height: 132,
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
          Positioned(
            right: -30,
            top: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0x382DD4BF), Color(0x002DD4BF)])),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('CURRENT THROUGHPUT', style: TextStyle(fontSize: 9.5, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: Color(0xFF8FB2C6))),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0x17FFFFFF), borderRadius: BorderRadius.circular(99), border: Border.all(color: const Color(0x24FFFFFF))),
                      child: Text(
                        state.pausedGlobally ? '已暂停' : '全局不限速',
                        style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFBFE6F5)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatSpeed(speed).replaceAll('/s', ''),
                      style: const TextStyle(fontSize: 31, height: 1, fontWeight: FontWeight.w800, letterSpacing: -1, color: Colors.white),
                    ),
                    const SizedBox(width: 4),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 3),
                      child: Text('↓', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF9EBBCE))),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text('上传 ', style: const TextStyle(fontSize: 9.5, color: Color(0xFF8FA8BD))),
                    Text(formatSpeed(state.upSpeed), style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFFCFE6F3))),
                    const SizedBox(width: 12),
                    Text('活动任务 ', style: const TextStyle(fontSize: 9.5, color: Color(0xFF8FA8BD))),
                    Text('$active', style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFFCFE6F3))),
                    const SizedBox(width: 12),
                    Text('剩余 ', style: const TextStyle(fontSize: 9.5, color: Color(0xFF8FA8BD))),
                    Text(formatCountdown(eta), style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFFCFE6F3))),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  height: 44,
                  width: double.infinity,
                  child: CustomPaint(painter: _SparkPainter(history)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> values;
  _SparkPainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    final fill = Path();
    final points = values.isEmpty ? const [0.0, 0.0] : values;
    final maxValue = points.fold<double>(1, (max, e) => math.max(max, e));
    for (var i = 0; i < points.length; i++) {
      final x = points.length == 1 ? 0.0 : size.width * i / (points.length - 1);
      final y = size.height - (points[i] / maxValue) * (size.height - 6);
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(size.width, size.height);
    fill.close();
    canvas.drawPath(
      fill,
      Paint()..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x6138BDF8), Color(0x0038BDF8)],
      ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF7DD3FC)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter oldDelegate) => true;
}

class _StatTiles extends StatelessWidget {
  final TransfersState state;

  const _StatTiles({required this.state});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final doneBytes = state.done.fold<int>(0, (sum, e) => sum + e.done);
    final tiles = <List<String>>[
      ['arrow-down', '下载速度', formatSpeed(state.downSpeed)],
      ['arrow-up', '上传速度', formatSpeed(state.upSpeed)],
      ['zap', '队列', '${state.pendingCount} 项'],
      ['clock', '今日完成', formatBytes(doneBytes)],
    ];
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                color: p.isDark ? const Color(0xFF0F1D2C) : Colors.white,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: p.line2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      OlIcon(tiles[i][0], size: 11, color: p.ink4),
                      const SizedBox(width: 5),
                      Text(tiles[i][1], style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: p.ink4)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    tiles[i][2],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: p.ink),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TaskList extends ConsumerWidget {
  final List<TransferTask> tasks;
  final String tab;
  final ValueChanged<String> onTab;

  const _TaskList({required this.tasks, required this.tab, required this.onTab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    return Container(
      decoration: BoxDecoration(
        color: p.isDark ? const Color(0xFF0F1D2C) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.line2),
      ),
      child: Column(
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.line2))),
            child: Row(
              children: [
                Text('任务列表', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: p.ink2)),
                const Spacer(),
                OlSeg<String>(
                  items: const [
                    OlSegItem('all', '全部'),
                    OlSegItem('download', '下载'),
                    OlSegItem('upload', '上传'),
                    OlSegItem('failed', '失败'),
                  ],
                  value: tab,
                  onChanged: onTab,
                  height: 21,
                ),
              ],
            ),
          ),
          if (tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  OlIcon('inbox', size: 22, color: p.ink4),
                  const SizedBox(height: 8),
                  Text('队列是空的', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.ink2)),
                  const SizedBox(height: 3),
                  Text('在文件页右键下载，或在这里新建上传任务。', style: TextStyle(fontSize: 10, color: p.ink4)),
                ],
              ),
            )
          else
            for (final task in tasks) _TaskRow(task: task),
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
    final notifier = ref.read(transfersProvider.notifier);
    final eta = task.speed > 0 ? ((task.total - task.done) / task.speed).round() : 0;
    final statusLabel = switch (task.status) {
      TransferStatus.running => '${(task.progress * 100).round()}%',
      TransferStatus.paused => '已暂停',
      TransferStatus.queued => '排队中',
      TransferStatus.done => '已完成',
      TransferStatus.failed => '失败',
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.hairline))),
      child: Row(
        children: [
          FileGlyph(name: task.name, size: 30, radius: 8, iconSize: 15),
          const SizedBox(width: 9),
          Expanded(
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
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.ink),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(statusLabel, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: task.status == TransferStatus.failed ? const Color(0xFFD92D4B) : p.ink3)),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      task.kind == TransferKind.download ? '${task.serverLabel} → 本地' : '本地 → ${task.serverLabel}',
                      style: TextStyle(fontSize: 9, color: p.ink4),
                    ),
                    const SizedBox(width: 7),
                    if (task.status == TransferStatus.running)
                      Text(formatSpeed(task.speed), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: p.ink2)),
                    const SizedBox(width: 7),
                    Text('${formatBytes(task.done)} / ${formatBytes(task.total)}', style: TextStyle(fontSize: 9, color: p.ink4)),
                    if (task.error != null) ...[
                      const SizedBox(width: 7),
                      Flexible(child: Text(task.error!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: Color(0xFFD92D4B)))),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                OlProgress(value: task.progress, height: 3),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  task.status == TransferStatus.running ? '剩余 ${formatCountdown(eta)}' : (task.status == TransferStatus.failed ? '可重试' : ''),
                  style: TextStyle(fontSize: 8.5, color: p.ink4),
                  textAlign: TextAlign.right,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          if (task.status == TransferStatus.running)
            OlIconButton(icon: 'pause', size: 24, iconSize: 12, tooltip: '暂停', onTap: () => notifier.pause(task.id))
          else if (task.status == TransferStatus.paused || task.status == TransferStatus.queued)
            OlIconButton(icon: 'play', size: 24, iconSize: 12, tooltip: '继续', onTap: () => notifier.resume(task.id))
          else if (task.status == TransferStatus.failed)
            OlIconButton(icon: 'rotate', size: 24, iconSize: 12, tooltip: '重试', onTap: () => notifier.retry(task.id)),
          OlIconButton(icon: 'x', size: 24, iconSize: 12, tooltip: '移除', onTap: () => notifier.remove(task.id)),
        ],
      ),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  final String text;
  const _PanelTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: context.ol.ink4),
      ),
    );
  }
}

class _LimitRow extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const _LimitRow({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final options = const [0, 1024, 5120, 10240];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink2)),
              const Spacer(),
              Text(value == 0 ? '不限' : '${value ~/ 1024} MB/s', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: p.ink3)),
            ],
          ),
          const SizedBox(height: 5),
          Wrap(
            spacing: 5,
            children: [
              for (final option in options)
                OlChip(
                  label: option == 0 ? '不限' : '${option ~/ 1024}M',
                  height: 22,
                  selected: value == option,
                  onTap: () => onChanged(option),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CheckLine extends StatelessWidget {
  final String label;
  final bool checked;
  final ValueChanged<bool>? onChanged;
  const _CheckLine({required this.label, required this.checked, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          OlCheckbox(value: checked, onChanged: onChanged),
          const SizedBox(width: 7),
          Expanded(child: Text(label, style: TextStyle(fontSize: 10, color: p.ink2))),
        ],
      ),
    );
  }
}

class _ServerTaskList extends StatelessWidget {
  final List<ServerTask> tasks;
  const _ServerTaskList({required this.tasks});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    if (tasks.isEmpty) {
      return Text('暂无服务端任务（离线下载 / 复制）', style: TextStyle(fontSize: 9, color: p.ink4));
    }
    return Column(
      children: [
        for (final task in tasks.take(6))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(child: Text(task.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9.5, color: p.ink2))),
                Text('${task.progress}%', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: p.ink3)),
              ],
            ),
          ),
      ],
    );
  }
}

class _MobileSpeedCard extends StatelessWidget {
  final TransfersState state;
  const _MobileSpeedCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final total = state.downSpeed + state.upSpeed;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0C2133), Color(0xFF0E3A46)]),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CURRENT THROUGHPUT', style: TextStyle(fontSize: 8.5, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: Color(0xFF8FB2C6))),
          const SizedBox(height: 5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatSpeed(total).replaceAll('/s', ''), style: const TextStyle(fontSize: 29, height: 1, fontWeight: FontWeight.w800, letterSpacing: -1, color: Colors.white)),
              const SizedBox(width: 3),
              const Padding(padding: EdgeInsets.only(bottom: 3), child: Text('/s', style: TextStyle(fontSize: 10, color: Color(0xFF9EBBCE)))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('下载 ', style: const TextStyle(fontSize: 9, color: Color(0xFF8FA8BD))),
              Text(formatSpeed(state.downSpeed), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFD6E9F5))),
              const SizedBox(width: 12),
              Text('上传 ', style: const TextStyle(fontSize: 9, color: Color(0xFF8FA8BD))),
              Text(formatSpeed(state.upSpeed), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFD6E9F5))),
              const SizedBox(width: 12),
              Text('活动 ', style: const TextStyle(fontSize: 9, color: Color(0xFF8FA8BD))),
              Text('${state.active.length}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFD6E9F5))),
            ],
          ),
        ],
      ),
    );
  }
}

class _MobileTaskCard extends ConsumerWidget {
  final TransferTask task;
  const _MobileTaskCard({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final notifier = ref.read(transfersProvider.notifier);
    final eta = task.speed > 0 ? ((task.total - task.done) / task.speed).round() : 0;
    final route = task.kind == TransferKind.download
        ? '${task.serverLabel} → 本地'
        : '本地 → ${task.serverLabel}';
    final statusLine = task.status == TransferStatus.failed
        ? (task.error ?? '传输失败')
        : '$route · ${formatSpeed(task.speed)}';
    final bottomLeft = '${formatBytes(task.done)} / ${formatBytes(task.total)}';
    final bottomRight = task.status == TransferStatus.failed
        ? '可重试'
        : (task.status == TransferStatus.done
            ? '已完成'
            : (task.status == TransferStatus.paused
                ? '已暂停'
                : (task.status == TransferStatus.queued ? '排队中' : '剩余 ${formatCountdown(eta)}')));
    final pct = (task.progress * 100).round();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.line2),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FileGlyph(name: task.name, size: 32, radius: 9, iconSize: 16),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: p.ink)),
                    const SizedBox(height: 2),
                    Text(
                      statusLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 8.5, color: task.status == TransferStatus.failed ? const Color(0xFFD92D4B) : p.ink4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text('$pct%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF0B85AE))),
              const SizedBox(width: 2),
              OlIconButton(
                icon: task.status == TransferStatus.running
                    ? 'pause'
                    : (task.status == TransferStatus.failed ? 'rotate' : 'play'),
                size: 24,
                iconSize: 12,
                onTap: () {
                  if (task.status == TransferStatus.running) {
                    notifier.pause(task.id);
                  } else if (task.status == TransferStatus.failed) {
                    notifier.retry(task.id);
                  } else {
                    notifier.resume(task.id);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 9),
          OlProgress(value: task.progress, height: 4),
          const SizedBox(height: 7),
          Row(
            children: [
              Text(bottomLeft, style: TextStyle(fontSize: 8.5, color: p.ink4)),
              const Spacer(),
              if (bottomRight.isNotEmpty)
                Text(
                  bottomRight,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w600,
                    color: task.status == TransferStatus.failed ? const Color(0xFFD92D4B) : p.ink3,
                  ),
                ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => notifier.remove(task.id),
                child: Text('移除', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: p.ink4)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final String icon;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: p.surfaceAlt, shape: BoxShape.circle, border: Border.all(color: p.line2)),
        child: Center(child: OlIcon(icon, size: 16, color: p.ink3)),
      ),
    );
  }
}
