import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/frame.dart';
import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/file_widgets.dart';
import '../../core/widgets/ol_controls.dart';
import '../../core/widgets/ol_dialogs.dart';
import '../../core/widgets/ol_icon.dart';
import 'file_actions.dart';

class FavoritesPage extends ConsumerStatefulWidget {
  final String initialTab;
  const FavoritesPage({super.key, this.initialTab = 'star'});

  @override
  ConsumerState<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends ConsumerState<FavoritesPage> {
  late String _tab = widget.initialTab == 'recent' ? 'recent' : 'star';

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 900;
    final body = narrow ? _buildMobile(context) : _buildDesktop(context);
    return AppFrame(navIndex: 2, child: body);
  }

  Widget _buildDesktop(BuildContext context) {
    final p = context.ol;
    return Container(
      color: p.card,
      child: Column(
        children: [
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.hairline))),
            child: Row(
              children: [
                Text('收藏与最近', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p.ink)),
                const SizedBox(width: 14),
                OlSeg<String>(
                  items: const [
                    OlSegItem('star', '收藏', icon: 'star'),
                    OlSegItem('recent', '最近使用', icon: 'clock'),
                  ],
                  value: _tab,
                  onChanged: (v) => setState(() => _tab = v),
                ),
                const Spacer(),
                OlGhostButton(label: '返回文件', icon: 'folder', onTap: () => context.go('/files')),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: _tab == 'star' ? const _FavoriteList() : const _RecentList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobile(BuildContext context) {
    final p = context.ol;
    return Column(
      children: [
        Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.centerLeft,
          child: Text('收藏', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: p.ink)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              OlChip(label: '收藏', icon: 'star', selected: _tab == 'star', onTap: () => setState(() => _tab = 'star')),
              const SizedBox(width: 6),
              OlChip(label: '最近使用', icon: 'clock', selected: _tab == 'recent', onTap: () => setState(() => _tab = 'recent')),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(child: _tab == 'star' ? const _FavoriteList() : const _RecentList()),
      ],
    );
  }
}

class _FavoriteList extends ConsumerWidget {
  const _FavoriteList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(sessionProvider).profile;
    final entries = ref.watch(favoritesProvider).where((e) => e.serverId == profile?.id).toList();
    final p = context.ol;

    if (entries.isEmpty) {
      return OlEmptyState(
        icon: 'star',
        title: '还没有收藏',
        subtitle: '在文件列表右键或「更多」菜单里点「收藏」，常用文件会出现在这里。',
        action: OlPrimaryButton(label: '去浏览文件', icon: 'folder', onTap: () => context.go('/files')),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: entries.length,
      separatorBuilder: (_, __) => Divider(color: p.line2, height: 1),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final item = entry.toItem();
        return InkWell(
          onTap: () async {
            if (entry.isDir) {
              await ref.read(filesProvider.notifier).open(entry.path);
              if (context.mounted) context.go('/files');
            } else {
              await previewItem(context, ref, item);
            }
          },
          onSecondaryTapDown: (details) async {
            await showOlMenu(context, position: details.globalPosition, items: [
              OlMenuItem('打开', 'external', () async {
                if (entry.isDir) {
                  await ref.read(filesProvider.notifier).open(entry.path);
                  if (context.mounted) context.go('/files');
                } else {
                  await previewItem(context, ref, item);
                }
              }),
              OlMenuItem('从收藏移除', 'trash', () async {
                await ref.read(favoritesProvider.notifier).removeEntry(entry);
                if (context.mounted) olToast(context, '已移除收藏');
              }, danger: true),
            ]);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
            child: Row(
              children: [
                FileGlyph(item: item, size: 32, radius: 9, iconSize: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.ink)),
                      const SizedBox(height: 2),
                      Text(entry.path, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9.5, fontFamily: 'monospace', color: p.ink4)),
                    ],
                  ),
                ),
                Text(relativeTime(entry.addedAt), style: TextStyle(fontSize: 9.5, color: p.ink4)),
                const SizedBox(width: 8),
                OlIconButton(
                  icon: 'x',
                  size: 24,
                  iconSize: 12,
                  tooltip: '移除',
                  onTap: () async {
                    await ref.read(favoritesProvider.notifier).removeEntry(entry);
                    if (context.mounted) olToast(context, '已移除收藏');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RecentList extends ConsumerWidget {
  const _RecentList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(sessionProvider).profile;
    if (profile == null) return const SizedBox.shrink();
    final recent = ref.watch(serverStoreProvider).readRecent(profile.id);
    final p = context.ol;

    if (recent.isEmpty) {
      return const OlEmptyState(
        icon: 'clock',
        title: '还没有浏览记录',
        subtitle: '打开过的目录会记录在这里，切换服务器时不会互相污染。',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: recent.length,
      separatorBuilder: (_, __) => Divider(color: p.line2, height: 1),
      itemBuilder: (context, index) {
        final entry = recent[index];
        final path = (entry['path'] ?? '/').toString();
        final at = DateTime.tryParse((entry['at'] ?? '').toString());
        return InkWell(
          onTap: () async {
            await ref.read(filesProvider.notifier).open(path);
            if (context.mounted) context.go('/files');
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(9), border: Border.all(color: p.line2)),
                  child: Center(child: OlIcon('folder', size: 15, color: p.ink3)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(path == '/' ? '根目录' : baseName(path), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.ink)),
                      const SizedBox(height: 2),
                      Text(path, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9.5, fontFamily: 'monospace', color: p.ink4)),
                    ],
                  ),
                ),
                Text(relativeTime(at), style: TextStyle(fontSize: 9.5, color: p.ink4)),
                const SizedBox(width: 6),
                OlIcon('chev-r', size: 13, color: p.ink4),
              ],
            ),
          ),
        );
      },
    );
  }
}
