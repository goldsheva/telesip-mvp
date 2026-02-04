import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/auth/state/auth_notifier.dart';
import 'package:app/features/sip_users/models/sip_user.dart';
import 'package:app/features/sip_users/state/sip_users_provider.dart';
import 'package:app/ui/pages/dialer_page.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(sipUsersProvider);
    await ref.read(sipUsersProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sipUsers = ref.watch(sipUsersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'SIP Users',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(sipUsersProvider),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () => ref.read(authNotifierProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: sipUsers.when(
          loading: () =>
              const _CenteredScroll(child: CircularProgressIndicator()),
          error: (e, _) => _CenteredScroll(
            child: _ErrorState(
              message: e.toString(),
              onRetry: () => ref.invalidate(sipUsersProvider),
            ),
          ),
          data: (state) {
            if (state.items.isEmpty) {
              return _CenteredScroll(
                child: _EmptyState(
                  onRefresh: () => ref.invalidate(sipUsersProvider),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: state.items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (_, index) =>
                  _SipUserTile(sipUser: state.items[index]),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const DialerPage())),
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
        const Icon(Icons.person_off, size: 52),
        const SizedBox(height: 10),
        Text(
          'No SIP users',
          style: t.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Text(
          'Pull to refresh or try again.',
          style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 14),
        ElevatedButton(onPressed: onRefresh, child: const Text('Refresh')),
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
          'Failed to load SIP users',
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
        ElevatedButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    );
  }
}

class _SipUserTile extends StatelessWidget {
  const _SipUserTile({required this.sipUser});

  final SipUser sipUser;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      ),
      tileColor: Theme.of(context).colorScheme.surface,
      title: Text(
        sipUser.sipLogin,
        style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ID: ${sipUser.sipUserId}', style: t.bodySmall),
          if (sipUser.dongleId != null)
            Text('Dongle #: ${sipUser.dongleId}', style: t.bodySmall),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}
