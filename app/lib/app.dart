import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/config/app_theme.dart';
import 'package:app/state/auth/auth_controller.dart';
import 'package:app/state/auth/auth_state.dart';
import 'package:app/ui/pages/login_page.dart';
import 'package:app/ui/pages/home_page.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    return auth.when(
      loading: () => const _Splash(),
      error: (e, _) => LoginPage(error: e.toString()),
      data: (s) {
        return switch (s.status) {
          AuthStatus.authenticated => const HomePage(),
          AuthStatus.unauthenticated => LoginPage(error: s.error),
          AuthStatus.unknown => const _Splash(),
        };
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
