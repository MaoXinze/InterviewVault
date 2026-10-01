import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'core/widgets/splash.dart';
import 'core/widgets/theme_reveal.dart';
import 'data/database/app_database.dart';
import 'data/demo/demo_seed.dart';

/// 演示构建开关：flutter build apk --release --dart-define=DEMO_SEED=true
/// 首次启动（面试表为空）自动填充演示数据；正式构建不含填充路径。
const _demoSeed = bool.fromEnvironment('DEMO_SEED');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_demoSeed) {
    final db = AppDatabase();
    await seedDemoDataIfEmpty(db);
    await db.close();
  }
  runApp(const ProviderScope(child: InterviewVaultApp()));
}

class InterviewVaultApp extends ConsumerStatefulWidget {
  const InterviewVaultApp({super.key});

  @override
  ConsumerState<InterviewVaultApp> createState() =>
      _InterviewVaultAppState();
}

class _InterviewVaultAppState extends ConsumerState<InterviewVaultApp> {
  /// 开屏只播一次：播完从树上移除（不参与路由，返回键/深链不受影响）
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final reveal = ref.watch(themeRevealControllerProvider);
    final splashEnabled = ref.watch(splashEnabledProvider);
    return ThemeRevealHost(
      controller: reveal,
      child: MaterialApp.router(
        title: 'InterviewVault',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        routerConfig: appRouter,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        locale: const Locale('zh'),
        builder: (context, child) {
          return Stack(
            children: [
              child!,
              if (splashEnabled && !_splashDone)
                SplashOverlay(onDone: () => setState(() => _splashDone = true)),
            ],
          );
        },
      ),
    );
  }
}
