import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/app_info.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_icon.dart';

/// W6 设置侧栏。
///
/// 顺序按 v2.1 设计稿：服务器管理 / 存储挂载 / 传输 / 播放与预览 / 外观 / 关于与更新。
/// 「通知」与「隐私与安全」已移除（其能力并入传输与关于）；「退出登录」放在关于页底部。
class SettingsSidebar extends ConsumerWidget {
  final String active;
  final ValueChanged<String>? onSelect;
  const SettingsSidebar({super.key, required this.active, this.onSelect});

  static const items = <List<String>>[
    ['servers', '服务器管理', 'server', '/servers'],
    // v2.3：下载目录排在传输之上，与移动端「我的」列表一致。
    ['download', '下载目录', 'download', '/settings/download'],
    ['transfer', '传输', 'arrow-down', '/settings/transfer'],
    ['playback', '播放与预览', 'play', '/settings/playback'],
    ['appearance', '外观', 'sun', '/settings/appearance'],
    ['about', '关于与更新', 'info', '/settings/about'],
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.ol;
    final session = ref.watch(sessionProvider);

    void open(String key, String route) {
      if (key == 'servers') {
        context.push('/servers');
        return;
      }
      onSelect?.call(key);
      context.go(route);
    }

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
          const OlSectionLabel('设置'),
          for (final item in items)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => open(item[0], item[3]),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  height: 31,
                  margin: const EdgeInsets.only(bottom: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  decoration: BoxDecoration(
                    color: active == item[0] ? p.navOnBg : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      OlIcon(item[2], size: 15, color: active == item[0] ? OlTokens.sky600 : p.navIcon),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item[1],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active == item[0] ? p.navOn : p.nav),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            child: Text(
              '${AppInfo.shortLabel}\n${session.profile?.version ?? session.site?.version ?? 'API v4'} · ${_platformLabel()}\n便携数据 · userdata/',
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
