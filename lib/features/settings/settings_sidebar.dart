import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_icon.dart';
import '../../app/providers.dart';

class SettingsSidebar extends ConsumerWidget {
  final String active;
  const SettingsSidebar({super.key, required this.active});

  static const items = <List<String>>[
    ['servers', '服务器管理', 'server', '/servers'],
    ['storage', '存储挂载', 'database', '/settings?tab=storage'],
    ['transfer', '传输', 'arrow-down', '/settings?tab=transfer'],
    ['playback', '播放与预览', 'play', '/settings?tab=playback'],
    ['appearance', '外观', 'sun', '/settings?tab=appearance'],
    ['notify', '通知', 'bell', '/settings?tab=notify'],
    ['security', '隐私与安全', 'key', '/settings?tab=security'],
    ['about', '关于与更新', 'info', '/settings?tab=about'],
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final session = ref.watch(sessionProvider);
    final storages = ref.watch(storagesProvider).valueOrNull ?? const [];
    return Container(
      width: 204,
      color: p.surface,
      padding: const EdgeInsets.fromLTRB(9, 4, 9, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OlSectionLabel('设置'),
          for (final item in items)
            InkWell(
              onTap: () => context.go(item[3]),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 31,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                decoration: BoxDecoration(
                  color: active == item[0] ? p.navOnBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    OlIcon(item[2], size: 15, color: active == item[0] ? const Color(0xFF0EA5E9) : p.navIcon),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item[1],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active == item[0] ? p.navOn : p.nav),
                      ),
                    ),
                    if (item[0] == 'storage' && storages.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: active == item[0] ? p.card : p.navBadgeBg, borderRadius: BorderRadius.circular(5)),
                        child: Text('${storages.length}', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: p.ink3)),
                      ),
                  ],
                ),
              ),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            child: Text(
              'OpenList Client 1.0.3\n${session.profile?.version ?? session.site?.version ?? 'API v4'} · ${_platformLabel()}\n便携数据 · userdata/',
              style: TextStyle(fontSize: 8.5, height: 1.7, color: p.ink4),
            ),
          ),
        ],
      ),
    );
  }

  String _platformLabel() {
    if (Platform.isWindows) return 'Windows x64';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return Platform.operatingSystem;
  }
}
