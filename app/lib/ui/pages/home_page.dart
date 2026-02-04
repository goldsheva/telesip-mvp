import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/state/auth/auth_controller.dart';
import 'package:app/state/dongles/dongles_providers.dart';
import 'package:app/ui/pages/dialer_page.dart';
import 'package:app/ui/widgets/dongle_card.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(dongleListProvider);
    await ref.read(dongleListProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dongles = ref.watch(dongleListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Dongles',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(dongleListProvider),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: dongles.when(
          loading: () => const _CenteredScroll(child: CircularProgressIndicator()),
          error: (e, _) => _CenteredScroll(
            child: _ErrorState(
              message: e.toString(),
              onRetry: () => ref.invalidate(dongleListProvider),
            ),
          ),
          data: (items) {
            if (items.isEmpty) {
              return _CenteredScroll(
                child: _EmptyState(
                  onRefresh: () => ref.invalidate(dongleListProvider),
                ),
              );
            }

            final w = MediaQuery.of(context).size.width;
            final cols = w < 650 ? 1 : (w < 1100 ? 2 : 4);

            return Padding(
              padding: const EdgeInsets.all(16),
              child: GridView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: items.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.45,
                ),
                itemBuilder: (_, i) => DongleCard(dongle: items[i]),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DialerPage()),
        ),
        child: const Icon(Icons.dialpad),
      ),
    );
  }
}

class _CenteredScroll extends StatelessWidget {
  const _CenteredScroll({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Center(child: child),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.usb_rounded, size: 52),
        const SizedBox(height: 10),
        Text(
          'No dongles',
          style: t.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          'Pull to refresh or try again.',
          style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 14),
        ElevatedButton(
          onPressed: onRefresh,
          child: const Text('Refresh'),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline_rounded, size: 52),
        const SizedBox(height: 10),
        Text(
          'Failed to load dongles',
          style: t.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
          maxLines: 6,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 14),
        ElevatedButton(
          onPressed: onRetry,
          child: const Text('Try again'),
        ),
      ],
    );
  }
}
