import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/tokens.dart';
import '../features/auth/login_page.dart';
import '../features/auth/session.dart';
import '../features/files/favorites_page.dart';
import '../features/files/files_page.dart';
import '../features/media/player_page.dart';
import '../features/search/search_page.dart';
import '../features/servers/server_edit_page.dart';
import '../features/servers/servers_page.dart';
import '../features/settings/settings_page.dart';
import '../features/transfers/transfers_page.dart';
import 'providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);
  ref.listen<SessionState>(sessionProvider, (previous, next) {
    if (previous?.signedIn != next.signedIn) refresh.value++;
  });

  return GoRouter(
    initialLocation: '/files',
    refreshListenable: refresh,
    redirect: (context, state) {
      final signedIn = ref.read(sessionProvider).signedIn;
      final path = state.uri.path;
      final onLogin = path == '/login';
      // 服务器管理在未登录时也必须可进：首次运行要能添加实例，否则登录页的
      // 「服务器管理」入口会被登录守卫弹回 /login（v1.0.5 的 bug）。
      final serverArea = path == '/servers' || path.startsWith('/servers/');
      if (!signedIn && !onLogin && !serverArea) return '/login';
      if (signedIn && onLogin) return '/files';
      return null;
    },
    errorBuilder: (context, state) => _RouteError(message: state.error?.toString() ?? '页面不存在'),
    routes: [
      GoRoute(path: '/', redirect: (context, state) => '/files'),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/files',
        builder: (context, state) => FilesPage(initialPath: state.uri.queryParameters['path']),
      ),
      GoRoute(path: '/transfers', builder: (context, state) => const TransfersPage()),
      GoRoute(
        path: '/favorites',
        builder: (context, state) => FavoritesPage(initialTab: state.uri.queryParameters['tab'] ?? 'star'),
      ),
      GoRoute(
        path: '/search',
        builder: (context, state) => SearchPage(initialQuery: state.uri.queryParameters['q'] ?? ''),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => SettingsPage(tab: state.uri.queryParameters['tab'] ?? 'appearance'),
      ),
      // 设置分区用独立路径：只改 query 时同一条路由不会重建页面，
      // 表现为「点了没反应」（v1.0.5 的 bug）。
      GoRoute(
        path: '/settings/:tab',
        builder: (context, state) => SettingsPage(tab: state.pathParameters['tab'] ?? 'appearance'),
      ),
      GoRoute(path: '/servers', builder: (context, state) => const ServersPage()),
      GoRoute(
        path: '/servers/edit/:id',
        builder: (context, state) => ServerEditPage(serverId: state.pathParameters['id'] ?? 'new'),
      ),
      GoRoute(
        path: '/player',
        builder: (context, state) => PlayerPage(
          path: state.uri.queryParameters['path'] ?? '',
          name: state.uri.queryParameters['name'] ?? '',
        ),
      ),
    ],
  );
});

class _RouteError extends StatelessWidget {
  final String message;
  const _RouteError({required this.message});

  @override
  Widget build(BuildContext context) {
    final p = context.ol;
    return Scaffold(
      backgroundColor: p.card,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('404', style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: p.ink)),
            const SizedBox(height: 8),
            Text(message, style: TextStyle(fontSize: 12, color: p.ink3)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => context.go('/files'),
              child: const Text('返回文件'),
            ),
          ],
        ),
      ),
    );
  }
}
