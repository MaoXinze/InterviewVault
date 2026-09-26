import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'core/widgets/theme_reveal.dart';

void main() {
  runApp(const ProviderScope(child: InterviewVaultApp()));
}

class InterviewVaultApp extends ConsumerWidget {
  const InterviewVaultApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final reveal = ref.watch(themeRevealControllerProvider);
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
      ),
    );
  }
}
