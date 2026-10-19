import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../core/theme/tokens.dart';
import '../core/widgets/ol_controls.dart';
import '../core/widgets/ol_dialogs.dart';
import '../core/widgets/ol_icon.dart';
import 'providers.dart';

/// Desktop window chrome (W1/W2…) + Android bottom navigation (A2/A3/A6).
class AppFrame extends ConsumerWidget {
  final Widget child;
  final int navIndex;
  final bool showNav;
  final bool showTitleBar;

  const AppFrame({
    super.key,
    required this.child,
    this.navIndex = 0,
    this.showNav = true,
    this.showTitleBar = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final narrow = MediaQuery.sizeOf(context).width < 900;
    final p = context.ol;
    Widget body = child;
    if (!narrow && showTitleBar) {
      body = Column(
        children: [
          const OlTitleBar(),
          Expanded(child: body),
        ],
      );
    }
    if (narrow && showNav) {
      body = Column(
        children: [
          Expanded(child: body),
          _BottomNav(index: navIndex),
        ],
      );
    }
    return Scaffold(
      backgroundColor: p.card,
      body: body,
    );
  }
}

class OlTitleBar extends ConsumerWidget {
  const OlTitleBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final session = ref.watch(sessionProvider);
    final servers = ref.watch(serverListProvider);
    final profile = session.profile;
    final canDrag = Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: p.isDark ? const Color(0xFF0B1622) : const Color(0xFFFBFDFF),
        border: Border(bottom: BorderSide(color: p.line2)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 13),
          const OlMark(size: 19, radius: 6, iconSize: 11),
          const SizedBox(width: 8),
          Text(
            'OpenList',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: p.isDark ? const Color(0xFFC3D4E2) : const Color(0xFF3B4F64), letterSpacing: -0.1),
          ),
          const SizedBox(width: 9),
          Container(width: 1, height: 12, color: p.line),
          const SizedBox(width: 7),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) async {
              final items = <OlMenuItem>[];
              for (final s in servers.servers) {
                items.add(OlMenuItem(
                  s.id == servers.activeId ? '${s.name} · 当前' : s.name,
                  'server',
                  () async {
                    if (s.id == servers.activeId) return;
                    await ref.read(sessionProvider.notifier).switchTo(s.id);
                    await ref.read(filesProvider.notifier).attach();
                  },
                ));
              }
              items.add(OlMenuItem('管理服务器…', 'settings', () => context.go('/servers')));
              items.add(OlMenuItem('添加服务器…', 'plus', () => context.go('/servers/edit/new')));
              await showOlMenu(context, position: details.globalPosition, items: items);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
              child: Row(
                children: [
                  OlDot(color: session.signedIn ? OlTokens.ok : OlTokens.warn, size: 5),
                  const SizedBox(width: 5),
                  Text(
                    profile?.displayHost ?? '未连接',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: p.isDark ? const Color(0xFF7890A6) : const Color(0xFF7C8FA3)),
                  ),
                  const SizedBox(width: 4),
                  OlIcon('chev-d', size: 9, color: p.ink4),
                ],
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) async {
                if (canDrag) await windowManager.startDragging();
              },
              onDoubleTap: () async {
                if (!canDrag) return;
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
              child: const SizedBox.expand(),
            ),
          ),
          if (canDrag) const _WindowControls(),
        ],
      ),
    );
  }
}

class _WindowControls extends StatelessWidget {
  const _WindowControls();

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Row(
      children: [
        _CtrlButton(
          icon: 'minus',
          color: p.ink3,
          onTap: () => windowManager.minimize(),
        ),
        _CtrlButton(
          icon: 'square',
          color: p.ink3,
          onTap: () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
        ),
        _CtrlButton(
          icon: 'x',
          color: p.isDark ? const Color(0xFF7890A6) : const Color(0xFF8B9AA9),
          onTap: () => windowManager.close(),
        ),
      ],
    );
  }
}

class _CtrlButton extends StatelessWidget {
  final String icon;
  final Color color;
  final VoidCallback onTap;

  const _CtrlButton({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 38,
          color: Colors.transparent,
          child: Center(child: OlIcon(icon, size: 12, color: color, strokeWidth: 1.6)),
        ),
      ),
    );
  }
}

class _BottomNav extends ConsumerWidget {
  final int index;

  const _BottomNav({required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final transfers = ref.watch(transfersProvider);
    final pending = transfers.pendingCount;
    final items = <_NavItem>[
      _NavItem('文件', 'folder', '/files'),
      _NavItem('传输', 'arrow-down', '/transfers', badge: pending),
      _NavItem('收藏', 'star', '/favorites'),
      _NavItem('我的', 'user', '/settings'),
    ];
    return Container(
      height: 70 + MediaQuery.paddingOf(context).bottom,
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: p.isDark ? const Color(0xFF0A1624) : const Color(0xFAFFFFFF),
        border: Border(top: BorderSide(color: p.line2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < items.length; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.go(items[i].route),
              child: SizedBox(
                width: 62,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        OlIcon(
                          items[i].icon,
                          size: 21,
                          color: i == index ? const Color(0xFF0782AE) : (p.isDark ? const Color(0xFF5E7488) : const Color(0xFF9AABBC)),
                          strokeWidth: i == index ? 2.1 : 1.9,
                        ),
                        if (items[i].badge > 0)
                          Positioned(
                            right: -7,
                            top: -4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(color: OlTokens.sky600, borderRadius: BorderRadius.circular(99)),
                              child: Text('${items[i].badge}', style: const TextStyle(fontSize: 7.5, fontWeight: FontWeight.w900, color: Colors.white)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      items[i].label,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: i == index ? const Color(0xFF0782AE) : (p.isDark ? const Color(0xFF5E7488) : const Color(0xFF9AABBC)),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      width: 3,
                      height: 3,
                      decoration: BoxDecoration(
                        color: i == index ? OlTokens.sky600 : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavItem {
  final String label;
  final String icon;
  final String route;
  final int badge;
  const _NavItem(this.label, this.icon, this.route, {this.badge = 0});
}
