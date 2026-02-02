import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/state/auth/auth_controller.dart';
import 'package:app/state/auth/auth_state.dart';
import 'package:app/ui/pages/login_page.dart';
import 'package:app/ui/pages/home_page.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    final screen = switch (auth.status) {
      AuthStatus.unknown => const _Splash(),
      AuthStatus.unauthenticated => LoginPage(error: auth.error),
      AuthStatus.authenticated => const HomePage(),
    };

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: screen,
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
