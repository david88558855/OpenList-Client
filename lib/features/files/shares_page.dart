import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';
import '../../core/widgets/workspace_nav.dart';

/// 「我的分享」独立页面（v1.0.14）。
///
/// 之前它和收藏 / 最近使用挤在同一个页面的三个标签里，返回按钮、标题、
/// 路由语义都是混的。现在拆成真正的独立路由 `/shares`：
///   - 桌面：左侧工作区导航 204 + 列表，顶部有返回；
///   - 移动端：顶部返回栏 + 列表（不是底部 tab，所以必须自带返回）。
class SharesPage extends ConsumerWidget {
  const SharesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (context.isNarrow) {
      return AppFrame(
        showNav: false,
        handleBack: true,
        onBack: () async {
          context.go('/files');
          return true;
        },
        child: const _MobileBody(),
      );
    }
    return AppFrame(
      handleBack: true,
      child: const Row(
        children: [
          _Sidebar(),
          Expanded(child: _DesktopBody()),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 左侧工作区导航（与文件 / 传输 / 收藏页保持一致）
// ---------------------------------------------------------------------------
class _Sidebar extends ConsumerWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;

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
              children: const [
                // 与文件 / 收藏 / 传输页共用同一份工作区导航
                WorkspaceNav(active: 'shares'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Text('分享由服务端创建，这里只读并跳转浏览器。', style: TextStyle(fontSize: 8.5, height: 1.6, color: p.ink4)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 主区
// ---------------------------------------------------------------------------
class _DesktopBody extends ConsumerWidget {
  const _DesktopBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    return ColoredBox(
      color: p.card,
      child: Column(
        children: [
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.hairline))),
            child: Row(
              children: [
                OlIconButton(icon: 'chev-l', size: 30, iconSize: 17, tooltip: '返回', onTap: () => goBackOrFiles(context)),
                const SizedBox(width: 8),
                Text('我的分享', style: TextStyle(fontSize: 18, letterSpacing: -0.5, fontWeight: FontWeight.w800, color: p.ink)),
                const Spacer(),
                OlGhostButton(
                  label: '刷新',
                  icon: 'refresh',
                  height: 30,
                  onTap: () => ref.invalidate(sharesProvider),
                ),
              ],
            ),
          ),
          const Expanded(child: _ShareList()),
        ],
      ),
    );
  }
}

class _MobileBody extends ConsumerWidget {
  const _MobileBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    return ColoredBox(
      color: p.card,
      child: Column(
        children: [
          SizedBox(
            height: 54,
            child: Row(
              children: [
                OlIconButton(icon: 'chev-l', size: 34, iconSize: 18, onTap: () => goBackOrFiles(context)),
                const SizedBox(width: 2),
                Text('我的分享', style: TextStyle(fontSize: 17, letterSpacing: -0.4, fontWeight: FontWeight.w800, color: p.ink)),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OlIconButton(icon: 'refresh', size: 34, iconSize: 17, onTap: () => ref.invalidate(sharesProvider)),
                ),
              ],
            ),
          ),
          const Expanded(child: _ShareList()),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 分享列表（只读 + 浏览器打开）
// ---------------------------------------------------------------------------
class _ShareList extends ConsumerWidget {
  const _ShareList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shares = ref.watch(sharesProvider);
    return shares.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (error, stack) => OlEmptyState(
        icon: 'alert',
        title: '无法读取分享列表',
        subtitle: '$error',
        action: OlGhostButton(label: '重试', icon: 'refresh', onTap: () => ref.invalidate(sharesProvider)),
      ),
      data: (items) {
        if (items.isEmpty) {
          return const OlEmptyState(
            icon: 'share',
            title: '还没有分享',
            subtitle: '在文件上点三点菜单选「分享」，创建带提取码的链接',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
          itemCount: items.length,
          separatorBuilder: (context, index) => Divider(height: 1, color: context.ol.divider),
          itemBuilder: (context, index) {
            final share = items[index];
            return _ShareRow(
              name: share.name ?? share.files ?? '分享 ${share.id}',
              subtitle: share.link ?? '/s/${share.id}',
              trailing: share.visits == null ? '' : '${share.visits} 次访问',
              onOpen: () async {
                final link = share.link;
                if (link == null || link.isEmpty) {
                  olToast(context, '该分享没有可用链接', error: true);
                  return;
                }
                final uri = Uri.tryParse(link);
                if (uri == null) return;
                final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
                if (!ok && context.mounted) olToast(context, '无法打开浏览器', error: true);
              },
            );
          },
        );
      },
    );
  }
}

class _ShareRow extends StatefulWidget {
  final String name;
  final String subtitle;
  final String trailing;
  final VoidCallback onOpen;
  const _ShareRow({required this.name, required this.subtitle, required this.trailing, required this.onOpen});

  @override
  State<_ShareRow> createState() => _ShareRowState();
}

class _ShareRowState extends State<_ShareRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onOpen,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          color: _hover ? p.rowHover : null,
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: const Color(0xFFE6F7FE), borderRadius: BorderRadius.circular(9)),
                child: const Center(child: OlIcon('link', size: 16, color: Color(0xFF0A93C4))),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 9.5, color: p.ink4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(widget.trailing, style: TextStyle(fontSize: 9.5, color: p.ink4)),
              const SizedBox(width: 6),
              OlIcon('external', size: 13, color: p.ink4),
            ],
          ),
        ),
      ),
    );
  }
}
