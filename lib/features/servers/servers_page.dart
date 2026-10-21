import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/models/server_profile.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';
import 'server_form.dart';

class ServersPage extends ConsumerStatefulWidget {
  const ServersPage({super.key});

  @override
  ConsumerState<ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends ConsumerState<ServersPage> {
  String? _selectedId;
  String _query = '';
  String _filter = 'all';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 900;
    final body = narrow ? _buildMobile(context) : _buildDesktop(context);
    return AppFrame(showNav: false, child: body);
  }

  List<ServerProfile> _filtered(List<ServerProfile> servers) {
    var list = servers;
    if (_filter == 'ok') {
      list = list.where((e) => e.health == ServerHealth.ok).toList();
    } else if (_filter == 'error') {
      list = list.where((e) => e.health != ServerHealth.ok).toList();
    }
    if (_query.trim().isNotEmpty) {
      final q = _query.trim().toLowerCase();
      list = list.where((e) => e.name.toLowerCase().contains(q) || e.baseUrl.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  /// 点击服务器 = 切换为当前实例，并直接进入它上次浏览的文件夹。
  Future<void> _switchTo(ServerProfile profile, {bool open = true}) async {
    final settings = ref.read(appSettingsProvider);
    if (settings.pauseOnSwitch) {
      await ref.read(transfersProvider.notifier).pauseAll();
    }
    // v2.6：switchTo 内部已负责 setActive + boot + files.attach，
    // 这里不再重复 attach（否则空目录会被连续请求两次）。
    await ref.read(sessionProvider.notifier).switchTo(profile.id);
    if (!context.mounted) return;
    if (!ref.read(sessionProvider).signedIn) {
      // 该实例还没有可用凭据：直接带地址去登录页，而不是留在原地提示一句。
      olToast(context, '「${profile.name}」需要重新登录');
      context.go('/login');
      return;
    }
    if (open) {
      _backToPrevious(context);
    } else {
      olToast(context, '已切换到 ${profile.name}');
    }
  }

  Widget _buildDesktop(BuildContext context) {
    final p = context.ol;
    final serversState = ref.watch(serverListProvider);
    final session = ref.watch(sessionProvider);
    final servers = _filtered(serversState.servers);
    final isNew = _selectedId == 'new';
    final selected = serversState.servers.where((e) => e.id == (_selectedId ?? serversState.activeId)).toList();
    final editing = isNew ? null : (selected.isEmpty ? null : selected.first);

    return Row(
      children: [
        // v2.6：服务器管理不再复用「设置」侧栏，自带返回入口。
        // 之前它寄生在设置分区里，进去以后找不到回文件页的路，切分区还会整页缩放。
        _ServersRail(
          current: session.profile,
          count: serversState.count,
          onBack: () => goBackOrFiles(context),
        ),
        Expanded(
          child: Container(
            color: p.card,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('服务器管理', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: p.ink)),
                          const SizedBox(height: 4),
                          Text(
                            '${serversState.count} 个服务器 · 数量不限 · 配置与缓存按实例隔离',
                            style: TextStyle(fontSize: 10.5, color: p.ink4),
                          ),
                        ],
                      ),
                    ),
                    OlPrimaryButton(
                      label: '添加服务器',
                      icon: 'plus',
                      onTap: () => setState(() => _selectedId = 'new'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    SizedBox(
                      width: 196,
                      child: OlField(
                        controller: _search,
                        icon: 'search',
                        hint: '搜索名称或地址',
                        dense: true,
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OlChip(label: '全部 ${serversState.count}', selected: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
                    const SizedBox(width: 6),
                    OlChip(
                      label: '已连接 ${serversState.servers.where((e) => e.health == ServerHealth.ok).length}',
                      selected: _filter == 'ok',
                      onTap: () => setState(() => _filter = 'ok'),
                    ),
                    const SizedBox(width: 6),
                    OlChip(
                      label: '异常 ${serversState.servers.where((e) => e.health != ServerHealth.ok).length}',
                      selected: _filter == 'error',
                      onTap: () => setState(() => _filter = 'error'),
                    ),
                    const Spacer(),
                    if (session.profile != null)
                      OlChip(label: '当前：${session.profile!.name}', teal: true, icon: 'check'),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(
                              child: ListView(
                                children: [
                                  for (final server in servers)
                                    _ServerRow(
                                      server: server,
                                      current: server.id == serversState.activeId,
                                      selected: server.id == editing?.id,
                                      onSelect: () => setState(() => _selectedId = server.id),
                                      onSwitch: () => _switchTo(server),
                                      // v1.0.16：「编辑」打开独立编辑页（带返回），
                                      // 之前只是把右侧表单切到该服务器，若它已选中就完全没反馈。
                                      onEdit: () => context.push('/servers/edit/${server.id}'),
                                      onDelete: () async {
                                        final confirmed = await olConfirm(
                                          context,
                                          title: '删除「${server.name}」',
                                          message: '只移除本地配置与凭据，不影响服务端数据。',
                                          confirm: '删除',
                                          danger: true,
                                        );
                                        if (!confirmed) return;
                                        final wasActive = serversState.activeId == server.id;
                                        await ref.read(serverListProvider.notifier).remove(server.id);
                                        if (wasActive) await ref.read(sessionProvider.notifier).retry();
                                        if (context.mounted) olToast(context, '已删除 ${server.name}');
                                      },
                                      onReconnect: () async {
                                        final result = await ref.read(sessionProvider.notifier).probe(server.baseUrl);
                                        if (!context.mounted) return;
                                        if (result.ok) {
                                          await ref.read(serverListProvider.notifier).touch(
                                                server.id,
                                                latencyMs: result.latencyMs,
                                                health: ServerHealth.ok,
                                                siteTitle: result.site?.title,
                                                version: result.site?.version,
                                              );
                                          if (context.mounted) olToast(context, '连接正常 · ${result.latencyMs} ms');
                                        } else {
                                          await ref.read(serverListProvider.notifier).touch(server.id, health: ServerHealth.timeout);
                                          if (context.mounted) olToast(context, result.error ?? '连接失败', error: true);
                                        }
                                      },
                                    ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const OlIcon('info', size: 10, color: Color(0xFFB2C1CF)),
                                      const SizedBox(width: 5),
                                      Expanded(
                                        child: Text(
                                          '列表保存在本地，凭据写入系统安全存储；删除服务器只移除本地配置，不影响服务端数据。',
                                          style: TextStyle(fontSize: 8.5, height: 1.6, color: p.ink4),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _ConfigCard(
                                          title: '配置备份',
                                          child: Row(
                                            children: [
                                              OlChip(label: '导出', icon: 'external', height: 22, onTap: _exportConfig),
                                              const SizedBox(width: 5),
                                              OlChip(label: '导入', icon: 'download', height: 22, onTap: _importConfig),
                                            ],
                                          ),
                                          footer: '不含密码，仅地址与偏好',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 11),
                      Container(
                        width: 316,
                        decoration: BoxDecoration(
                          color: p.surfaceAlt,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: p.line2),
                        ),
                        child: isNew
                            ? ServerForm(
                                profile: null,
                                onClose: () => setState(() => _selectedId = null),
                                onSaved: () => setState(() => _selectedId = null),
                              )
                            : editing == null
                            ? Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const OlIcon('server', size: 16, color: OlTokens.sky600),
                                    const SizedBox(height: 8),
                                    Text('选择左侧服务器进行编辑，或添加一个新的实例。', style: TextStyle(fontSize: 11, height: 1.7, color: p.ink3)),
                                  ],
                                ),
                              )
                            : ServerForm(
                                profile: editing,
                                onClose: () => setState(() => _selectedId = 'new'),
                                onSaved: () => setState(() {}),
                                onDeleted: () => setState(() => _selectedId = null),
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
    final serversState = ref.watch(serverListProvider);
    final session = ref.watch(sessionProvider);
    final current = session.profile;
    final others = serversState.servers.where((e) => e.id != current?.id).toList();
    final settings = ref.watch(appSettingsProvider);

    return Container(
      color: p.card,
      child: Column(
        children: [
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                OlIconButton(icon: 'chev-l', size: 30, iconSize: 18, onTap: () => _backToPrevious(context)),
                const SizedBox(width: 6),
                Text('服务器', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: p.ink)),
                const Spacer(),
                Text('${serversState.count} 个 · 不限', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: p.ink4)),
                const SizedBox(width: 8),
                OlIconButton(icon: 'plus', size: 30, iconSize: 15, onTap: () => context.push('/servers/edit/new')),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                if (current != null) _CurrentServerCard(profile: current, signedIn: session.signedIn),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text('全部服务器', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: p.ink4)),
                    const Spacer(),
                    Text('其他 ${others.length} 个', style: TextStyle(fontSize: 9, color: p.ink4)),
                  ],
                ),
                const SizedBox(height: 8),
                for (final server in others) ...[
                  GestureDetector(
                    // 整卡可点：切换并打开该服务器的文件夹
                    onTap: () => _switchTo(server),
                    child: _MobileServerCard(
                    profile: server,
                    onSwitch: () => _switchTo(server),
                    onEdit: () => context.push('/servers/edit/${server.id}'),
                    onDelete: () async {
                      final confirmed = await olConfirm(
                        context,
                        title: '删除「${server.name}」',
                        message: '只移除本地配置与凭据，不影响服务端数据。',
                        confirm: '删除',
                        danger: true,
                      );
                      if (!confirmed) return;
                      await ref.read(serverListProvider.notifier).remove(server.id);
                      if (context.mounted) olToast(context, '已删除 ${server.name}');
                    },
                  ),
                  ),
                  const SizedBox(height: 8),
                ],
                GestureDetector(
                  onTap: () => context.push('/servers/edit/new'),
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: p.isDark ? const Color(0xFF243A52) : const Color(0xFFD8E4EF)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OlIcon('plus', size: 14, color: OlTokens.sky600),
                        const SizedBox(width: 6),
                        Text('添加服务器', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: const Color(0xFF0A93C4))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                  decoration: BoxDecoration(
                    color: p.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.line2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('切换行为', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: p.ink3)),
                      for (final row in <List<String>>[
                        ['切换时暂停旧任务', 'pause'],
                        ['恢复上次浏览位置', 'browse'],
                      ])
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              Text(row[0], style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.ink2)),
                              const Spacer(),
                              OlSwitch(
                                small: true,
                                value: row[1] == 'pause'
                                    ? settings.pauseOnSwitch
                                    : (current?.rememberBrowse ?? true),
                                onChanged: (v) async {
                                  if (row[1] == 'pause') {
                                    ref.read(appSettingsProvider.notifier).setPauseOnSwitch(v);
                                  } else if (current != null) {
                                    await ref.read(serverListProvider.notifier).upsert(current.copyWith(rememberBrowse: v));
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: OlGhostButton(label: '导出配置', icon: 'external', onTap: _exportConfig)),
                    const SizedBox(width: 8),
                    Expanded(child: OlGhostButton(label: '导入配置', icon: 'download', onTap: _importConfig)),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '删除服务器只移除本地配置，不影响服务端数据；凭据保存在系统 Keystore。',
                  style: TextStyle(fontSize: 8.5, height: 1.6, color: p.ink4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportConfig() async {
    final servers = ref.read(serverListProvider).servers;
    final payload = {
      'product': 'OpenList Client',
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'servers': servers.map((e) {
        final json = e.toJson();
        json.remove('lastUsed');
        return json;
      }).toList(),
    };
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}openlist-servers.json');
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
      if (!mounted) return;
      olToast(context, '已导出到 ${file.path}');
    } catch (_) {
      if (mounted) olToast(context, '导出失败，检查存储权限', error: true);
    }
  }

  Future<void> _importConfig() async {
    final result = await FilePicker.platform.pickFiles(withData: true, type: FileType.custom, allowedExtensions: ['json']);
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      final rawList = decoded is List ? decoded : (decoded is Map ? decoded['servers'] : null);
      if (rawList is! List) throw const FormatException('缺少 servers');
      var added = 0;
      for (final raw in rawList) {
        if (raw is! Map) continue;
        final profile = ServerProfile.fromJson({
          ...Map<String, dynamic>.from(raw),
          'id': newServerId(),
        });
        // 导入的地址同样要过安全校验，避免把公网 HTTP 实例带进配置。
        if (profile.baseUrl.isEmpty || validateBaseUrl(profile.baseUrl) != null) continue;
        await ref.read(serverListProvider.notifier).upsert(profile.copyWith(health: ServerHealth.unknown));
        added++;
      }
      if (!mounted) return;
      olToast(context, added == 0 ? '没有可导入的服务器' : '已导入 $added 个服务器（需重新登录）');
    } catch (_) {
      if (mounted) olToast(context, '配置文件格式不正确', error: true);
    }
  }
}

/// 服务器管理自己的左栏：只有「返回」与当前实例摘要。
/// 它是独立一级页面，不再带任何设置导航（v1.0.14：设置已挪到工作区）。
class _ServersRail extends StatelessWidget {
  final ServerProfile? current;
  final int count;
  final VoidCallback onBack;

  const _ServersRail({
    required this.current,
    required this.count,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    Widget item(String icon, String label, VoidCallback onTap) => MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 31,
              margin: const EdgeInsets.only(bottom: 1),
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Row(
                children: [
                  OlIcon(icon, size: 15, color: p.navIcon),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.nav),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

    return Container(
      width: 204,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(right: BorderSide(color: p.line2)),
      ),
      padding: const EdgeInsets.fromLTRB(9, 4, 9, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OlSectionLabel('导航'),
          item('chev-l', '返回', onBack),
          const OlSectionLabel('当前实例'),
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
            decoration: BoxDecoration(
              color: p.surfaceAlt,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: p.line2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current?.name ?? '未连接',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: p.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  current?.displayHost ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9, fontFamily: 'monospace', color: p.ink4),
                ),
                const SizedBox(height: 4),
                Text('共 $count 个服务器', style: TextStyle(fontSize: 9, color: p.ink4)),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            child: Text(
              '凭据写入系统安全存储\n删除只移除本地配置',
              style: TextStyle(fontSize: 8.5, height: 1.7, color: p.ink4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerRow extends StatelessWidget {
  final ServerProfile server;
  final bool current;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onSwitch;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onReconnect;

  const _ServerRow({
    required this.server,
    required this.current,
    required this.selected,
    required this.onSelect,
    required this.onSwitch,
    required this.onEdit,
    required this.onDelete,
    required this.onReconnect,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final healthColor = server.health == ServerHealth.ok
        ? const Color(0xFF0B7A63)
        : server.health == ServerHealth.timeout
            ? OlTokens.warnDeep
            : p.ink4;
    return GestureDetector(
      onTap: onSelect,
      onDoubleTap: onSwitch,
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        // v1.0.39：行整体略微加高，配合字号/按钮放大
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          gradient: current ? const LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Color(0xFFF5FCFE), Color(0xFFF7FEFC)]) : null,
          color: current ? null : p.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? OlTokens.sky : (current ? const Color(0xFFBFE9F7) : p.line2)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: current ? const Color(0xFFE9F8FF) : p.surfaceAlt, borderRadius: BorderRadius.circular(10)),
              child: Center(child: OlIcon('server', size: 17, color: current ? const Color(0xFF0A93C4) : p.ink3)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          server.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: p.ink),
                        ),
                      ),
                      if (current) ...[
                        const SizedBox(width: 6),
                        const OlBadge(label: '当前'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${server.baseUrl} · ${server.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, fontFamily: 'monospace', color: p.ink4),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 84,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OlDot(size: 4, color: server.health == ServerHealth.ok ? OlTokens.ok : (server.health == ServerHealth.timeout ? OlTokens.warn : p.ink4)),
                      const SizedBox(width: 4),
                      Text(
                        server.latencyMs != null ? '${server.latencyMs} ms' : (server.health == ServerHealth.timeout ? '超时' : '未连接'),
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: healthColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(relativeTime(server.lastUsed), style: TextStyle(fontSize: 9.5, color: p.ink4)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (!current) _TinyButton(label: '打开', primary: true, onTap: onSwitch),
            const SizedBox(width: 4),
            _TinyButton(label: '编辑', onTap: onEdit),
            GestureDetector(
              onTapDown: (details) async {
                await showOlMenu(context, position: details.globalPosition, items: [
                  OlMenuItem('编辑', 'edit', onEdit),
                  OlMenuItem('测试连接', 'zap', onReconnect),
                  OlMenuItem('删除', 'trash', onDelete, danger: true),
                ]);
              },
              child: Container(
                width: 27,
                height: 27,
                decoration: BoxDecoration(border: Border.all(color: p.line2), borderRadius: BorderRadius.circular(7), color: p.card),
                child: Center(child: OlIcon('more-v', size: 14, color: p.ink3)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TinyButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;

  const _TinyButton({required this.label, required this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // v1.0.16：改用 onTapDown 立即响应。行本身带 onDoubleTap（双击切换服务器），
      // 内层 onTap 会被双击判定拖住约 300ms，用户感知就是「点了编辑没反应」。
      onTapDown: (_) => onTap(),
      child: Container(
        // v1.0.39：按钮略微加大（23×9 → 27×10.5），点击区域更舒服
        height: 27,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: primary ? const Color(0xFFEAF8FE) : p.card,
          border: Border.all(color: primary ? const Color(0xFFCDEEFA) : p.line),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: primary ? const Color(0xFF08799F) : p.ink2),
          ),
        ),
      ),
    );
  }
}

class _ConfigCard extends StatelessWidget {
  final String title;
  final Widget child;
  final String footer;

  const _ConfigCard({required this.title, required this.child, required this.footer});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.line2)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: p.ink3)),
          const SizedBox(height: 6),
          child,
          const SizedBox(height: 5),
          Text(footer, style: TextStyle(fontSize: 8, color: p.ink4)),
        ],
      ),
    );
  }
}

class _CurrentServerCard extends StatelessWidget {
  final ServerProfile profile;
  final bool signedIn;

  const _CurrentServerCard({required this.profile, required this.signedIn});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0B2233), Color(0xFF0D3B46)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const OlMark(size: 26, radius: 8, iconSize: 12),
              const SizedBox(width: 8),
              const Text('CURRENT SERVER', style: TextStyle(fontSize: 8, letterSpacing: 1.6, fontWeight: FontWeight.w800, color: Color(0xFF9DB4C8))),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFF7DD3FC), borderRadius: BorderRadius.circular(5)),
                child: Text(
                  signedIn ? '已连接' : '待登录',
                  style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Color(0xFF0B5C4C)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(profile.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: Colors.white)),
          const SizedBox(height: 3),
          Text(profile.baseUrl, style: const TextStyle(fontSize: 9.5, fontFamily: 'monospace', color: Color(0xFF8FA8BD))),
          const SizedBox(height: 10),
          Row(
            children: [
              _DarkChip(label: '编辑', icon: 'edit', onTap: () => context.push('/servers/edit/${profile.id}')),
            ],
          ),
        ],
      ),
    );
  }
}

class _DarkChip extends StatelessWidget {
  final String label;
  final String icon;
  final VoidCallback onTap;
  const _DarkChip({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(color: const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(7), border: Border.all(color: const Color(0x24FFFFFF))),
        child: Row(
          children: [
            OlIcon(icon, size: 11, color: const Color(0xFFBFE6F5)),
            const SizedBox(width: 5),
            Text(label, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFFCFE6F3))),
          ],
        ),
      ),
    );
  }
}

class _MobileServerCard extends StatelessWidget {
  final ServerProfile profile;
  final VoidCallback onSwitch;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _MobileServerCard({required this.profile, required this.onSwitch, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    final (label, color) = switch (profile.health) {
      ServerHealth.ok => ('${profile.latencyMs ?? 0} ms', const Color(0xFF0B7A63)),
      ServerHealth.timeout => ('超时', OlTokens.warnDeep),
      ServerHealth.unauthorized => ('需登录', OlTokens.dangerDeep),
      ServerHealth.unknown => ('未连接', p.ink4),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line2)),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(9)),
                child: Center(child: OlIcon('server', size: 15, color: p.ink3)),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.ink)),
                    Text(profile.displayHost, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9.5, color: p.ink4)),
                  ],
                ),
              ),
              Text(label, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: color)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _TinyButton(label: profile.health == ServerHealth.timeout ? '重连' : '打开', primary: true, onTap: onSwitch),
              const SizedBox(width: 5),
              _TinyButton(label: '编辑', onTap: onEdit),
              const Spacer(),
              GestureDetector(
                onTapDown: (details) async {
                  await showOlMenu(context, position: details.globalPosition, items: [
                    OlMenuItem('编辑', 'edit', onEdit),
                    OlMenuItem('删除', 'trash', onDelete, danger: true),
                  ]);
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: OlIcon('more', size: 14, color: p.ink3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 返回上一页：从设置页 push 进来时回设置，从标题栏直接进来时回文件页。
void _backToPrevious(BuildContext context) {
  if (GoRouter.of(context).canPop()) {
    context.pop();
  } else {
    context.go('/files');
  }
}
