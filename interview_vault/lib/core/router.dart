import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/home/presentation/home_page.dart';
import '../features/interviews/presentation/interviews_page.dart';
import '../features/recording/presentation/recording_page.dart';
import '../features/review/presentation/review_page.dart';
import '../features/settings/presentation/settings_page.dart';

/// 四 Tab + 中央 ⏺（AGENTS 命名铁律：首页 / 面试 / ⏺ / 回顾 / 我的）。
///
/// 中央录音按钮不占 Tab 位：录音页为全屏路由，离开 Shell 以避免
/// 录音过程中误触 Tab 切换。
final appRouter = GoRouter(
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomePage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/interviews',
              builder: (context, state) => const InterviewsPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/review',
              builder: (context, state) => const ReviewPage(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsPage(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/record',
      builder: (context, state) => const RecordingPage(),
    ),
  ],
);

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _goBranch(int index) => navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      floatingActionButton: FloatingActionButton(
        key: const Key('tab_record'),
        onPressed: () => context.push('/record'),
        shape: const CircleBorder(),
        child: const Icon(Icons.fiber_manual_record),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 6,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _TabItem(
              icon: Icons.home_outlined,
              activeIcon: Icons.home,
              label: '首页',
              selected: navigationShell.currentIndex == 0,
              onTap: () => _goBranch(0),
            ),
            _TabItem(
              icon: Icons.work_outline,
              activeIcon: Icons.work,
              label: '面试',
              selected: navigationShell.currentIndex == 1,
              onTap: () => _goBranch(1),
            ),
            const SizedBox(width: 56),
            _TabItem(
              icon: Icons.style_outlined,
              activeIcon: Icons.style,
              label: '回顾',
              selected: navigationShell.currentIndex == 2,
              onTap: () => _goBranch(2),
            ),
            _TabItem(
              icon: Icons.person_outline,
              activeIcon: Icons.person,
              label: '我的',
              selected: navigationShell.currentIndex == 3,
              onTap: () => _goBranch(3),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = selected
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          // FittedBox 兜底：任何字体度量下都不溢出底栏高度。
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(selected ? activeIcon : icon, color: color, size: 24),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: color,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
