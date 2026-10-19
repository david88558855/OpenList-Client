import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/ol_controls.dart';
import '../settings/settings_sidebar.dart';
import 'server_form.dart';

class ServerEditPage extends ConsumerWidget {
  final String serverId;
  const ServerEditPage({super.key, required this.serverId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(serverListProvider).servers;
    final profile = servers.where((e) => e.id == serverId).toList();
    final narrow = MediaQuery.sizeOf(context).width < 900;
    final form = ServerForm(
      profile: profile.isEmpty ? null : profile.first,
      onSaved: () => context.go('/servers'),
      onDeleted: () => context.go('/servers'),
    );

    if (!narrow) {
      return AppFrame(
        showNav: false,
        child: Row(
          children: [
            const SettingsSidebar(active: 'servers'),
            Expanded(
              child: Container(
                color: context.ol.card,
                alignment: Alignment.topCenter,
                padding: const EdgeInsets.only(top: 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Container(
                    decoration: BoxDecoration(
                      color: context.ol.surfaceAlt,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: context.ol.line2),
                    ),
                    child: form,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final p = context.ol;
    return Scaffold(
      backgroundColor: p.card,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  OlIconButton(icon: 'chev-l', size: 30, iconSize: 18, onTap: () => context.go('/servers')),
                  const SizedBox(width: 4),
                  Text(
                    profile.isEmpty ? '添加服务器' : '编辑服务器',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: p.ink),
                  ),
                ],
              ),
            ),
            Expanded(child: form),
          ],
        ),
      ),
    );
  }
}
