import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/constants.dart';
import 'core/providers.dart';
import 'core/notify/reminder_service.dart';
import 'core/theme.dart';
import 'data/db/app_database.dart';
import 'data/repo/settings_repo.dart';
import 'data/seed/seeder.dart';
import 'ui/pages/plan_page.dart';
import 'ui/pages/qa_page.dart';
import 'ui/pages/settings_page.dart';
import 'ui/pages/stats_page.dart';
import 'ui/pages/today_page.dart';

/// 启动入口。
///
/// 铁律：runApp 必须是第一个不被阻塞的动作。
/// 只要 runApp 之前有任何一个 await 挂住（比如 MethodChannel 在真机上不返回），
/// Widget 树就永远不建，界面会永久停在原生 LaunchTheme 启动图，且不崩溃。
/// 所以这里所有初始化全部丢到 _bootstrap 里，首帧之后再跑。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase();

  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const StudyTrackerApp(),
    ),
  );

  unawaited(_bootstrap(db));
}

/// 首帧之后的初始化。每一步都独立兜底 + 超时，
/// 任何一步卡死或抛错都不影响已经起来的界面。
Future<void> _bootstrap(AppDatabase db) async {
  // 1) 首启导数据
  try {
    final r = await Seeder(db).seedIfNeeded().timeout(const Duration(seconds: 30));
    if (!r.ok && kDebugMode) {
      debugPrint('[SEED] failed fatal=' + (r.fatalError ?? '') + ' ' + r.failures().join(';'));
    }
  } on TimeoutException {
    debugPrint('[SEED] timeout 30s, skipped');
  } catch (e) {
    debugPrint('[SEED] throw ' + e.toString());
  }

  // 2) 通知服务
  try {
    await ReminderService().init().timeout(const Duration(seconds: 10));

    final SettingsRepo settings = SettingsRepo(db);
    final (int, int) t = await settings.reminderTime().timeout(const Duration(seconds: 10));
    final bool enabled = await settings.reminderEnabled().timeout(const Duration(seconds: 10));

    if (enabled) {
      await ReminderService()
          .schedule(hour: t.$1, minute: t.$2, database: db)
          .timeout(const Duration(seconds: 10));
    } else {
      await ReminderService().cancel().timeout(const Duration(seconds: 10));
    }
  } on TimeoutException {
    debugPrint('[REMINDER] timeout, skipped');
  } catch (e) {
    debugPrint('[REMINDER] init error: ' + e.toString());
  }
}

/// 应用根。只负责主题 + 路由。
class StudyTrackerApp extends StatelessWidget {
  const StudyTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: kAppName,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.system,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}

/// 五个 tab 用 StatefulShellRoute.indexedStack，
/// 好处：每个 tab 有自己的导航栈，切回去滚动位置和页面状态都还在。
final GoRouter _router = GoRouter(
  initialLocation: '/today',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return _AdaptiveScaffold(navigationShell: navigationShell);
      },
      branches: [
        StatefulShellBranch(routes: [_route('/', const TodayPage())]),
        StatefulShellBranch(routes: [_route('/plan', const PlanPage())]),
        StatefulShellBranch(routes: [_route('/stats', const StatsPage())]),
        StatefulShellBranch(routes: [_route('/qa', const QaPage())]),
        StatefulShellBranch(routes: [_route('/settings', const SettingsPage())]),
      ],
    ),
  ],
  redirect: (context, state) {
    if (state.uri.path == '/today') return '/';
    return null;
  },
);

GoRoute _route(String path, Widget page) {
  return GoRoute(path: path, builder: (context, state) => page);
}

/// 自适应用壳：窄屏底部导航，宽屏左侧导航。
class _AdaptiveScaffold extends StatelessWidget {
  const _AdaptiveScaffold({required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const List<NavigationDestination> _destinations = [
    NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: '今日'),
    NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: '计划'),
    NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: '统计'),
    NavigationDestination(icon: Icon(Icons.quiz_outlined), selectedIcon: Icon(Icons.quiz), label: '问答'),
    NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: '设置'),
  ];

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.of(context).size.width;
    final bool useRail = width >= AppConstants.breakpointDual;

    if (useRail) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: AppConstants.leftPaneWidth,
              child: NavigationRail(
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: _onTap,
                labelType: NavigationRailLabelType.all,
                destinations: _destinations
                    .map(
                      (d) => NavigationRailDestination(
                        icon: d.icon,
                        selectedIcon: d.selectedIcon,
                        label: Text(d.label),
                      ),
                    )
                    .toList(),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: navigationShell),
          ],
        ),
      );
    }

    // 折叠屏内屏 / 平板：底部导航，但内容限宽并居中。
    final bool limitWidth = width >= AppConstants.breakpointNarrow;
    final Widget body = limitWidth
        ? Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: navigationShell))
        : navigationShell;

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onTap,
        destinations: _destinations,
      ),
    );
  }
}
