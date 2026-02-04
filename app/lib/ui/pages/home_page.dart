import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/auth/state/auth_notifier.dart';
import 'package:app/features/dongles/models/dongle.dart';
import 'package:app/features/dongles/state/dongles_provider.dart';
import 'package:app/features/sip_users/models/pbx_sip_user.dart';
import 'package:app/features/sip_users/models/sip_users_state.dart';
import 'package:app/features/sip_users/state/sip_users_provider.dart';
import 'package:app/ui/pages/dialer_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  Future<void> _refresh() async {
    await Future.wait([
      ref.read(sipUsersProvider.notifier).refresh(),
      ref.read(donglesProvider.notifier).refresh(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final sipUsers = ref.watch(sipUsersProvider);
    final dongles = ref.watch(donglesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'SIP',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: () => ref.read(authNotifierProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: sipUsers.when(
        loading: () =>
            const _CenteredScroll(child: CircularProgressIndicator()),
        error: (e, _) => _CenteredScroll(
          child: _ErrorState(message: e.toString(), onRetry: _refresh),
        ),
        data: (state) => dongles.when(
          loading: () =>
              const _CenteredScroll(child: CircularProgressIndicator()),
          error: (e, _) => _CenteredScroll(
            child: _ErrorState(message: e.toString(), onRetry: _refresh),
          ),
          data: (dongleList) => _buildContent(context, state, dongleList),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    SipUsersState state,
    List<Dongle> dongles,
  ) {
    if (state.items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: _CenteredScroll(child: _EmptyState(onRefresh: _refresh)),
      );
    }

    final generalUser = state.items.firstWhere(
      (user) => user.dongleId == null,
      orElse: () => state.items.first,
    );
    final visibleUsers = state.items
        .where((user) => user.dongleId != null)
        .toList();

    if (visibleUsers.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: _CenteredScroll(child: _EmptyState(onRefresh: _refresh)),
      );
    }

    final dongleMap = {for (var dongle in dongles) dongle.dongleId: dongle};

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _GeneralSettingsCard(
                totalItems: visibleUsers.length,
                generalUser: generalUser,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Text(
                '${visibleUsers.length} SIP users',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final sipUser = visibleUsers[index];
                final dongle = sipUser.dongleId != null
                    ? dongleMap[sipUser.dongleId!]
                    : null;
                final isCallable = dongle?.isCallable ?? false;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _SipUserListTile(
                    sipUser: sipUser,
                    dongle: dongle,
                    isCallable: isCallable,
                    onCall: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DialerPage(sipUser: sipUser),
                      ),
                    ),
                  ),
                );
              }, childCount: visibleUsers.length),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
        ],
      ),
    );
  }
}

class _GeneralSettingsCard extends StatelessWidget {
  const _GeneralSettingsCard({
    required this.totalItems,
    required this.generalUser,
  });

  final int totalItems;
  final PbxSipUser generalUser;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _shadowColor(theme.shadowColor, 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'General settings',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Manage ${totalItems > 1 ? 'all' : 'the'} $totalItems SIP user${totalItems == 1 ? '' : 's'}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
          OutlinedButton.icon(
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (_) => _GeneralSettingsDialog(user: generalUser),
              );
            },
            icon: const Icon(Icons.info_outline),
            label: const Text('Details'),
          ),
        ],
      ),
    );
  }
}

class _SipUserListTile extends StatefulWidget {
  const _SipUserListTile({
    required this.sipUser,
    required this.dongle,
    required this.isCallable,
    required this.onCall,
  });

  final PbxSipUser sipUser;
  final Dongle? dongle;
  final bool isCallable;
  final VoidCallback onCall;

  @override
  State<_SipUserListTile> createState() => _SipUserListTileState();
}

class _SipUserListTileState extends State<_SipUserListTile> {

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryConnection = widget.sipUser.sipConnections.isNotEmpty
        ? widget.sipUser.sipConnections.first
        : null;
    final secondConnection = widget.sipUser.sipConnections.length > 1
        ? widget.sipUser.sipConnections[1]
        : null;
    final displayName =
        widget.dongle?.name ?? 'Dongle ${widget.sipUser.sipLogin}';
    final displayNumber = widget.dongle?.number;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _shadowColor(theme.shadowColor, 0.12),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    displayName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _InfoLine(label: 'SIP Username', value: widget.sipUser.sipLogin),
            const SizedBox(height: 6),
            _InfoLine(label: 'SIP Password', value: widget.sipUser.sipPassword),
            if (displayNumber != null && displayNumber.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(displayNumber, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 6),
            if (primaryConnection != null) ...[
              _InfoLine(label: 'SIP Server', value: primaryConnection.pbxSipUrl),
              const SizedBox(height: 6),
              _InfoLine(
                label: 'SIP Port',
                value: primaryConnection.pbxSipPort.toString(),
              ),
              const SizedBox(height: 6),
              _InfoLine(label: 'Protocol', value: primaryConnection.pbxSipProtocol),
            ],
            if (secondConnection != null) ...[
              const SizedBox(height: 6),
              _InfoLine(label: 'SIP Server', value: secondConnection.pbxSipUrl),
              const SizedBox(height: 6),
              _InfoLine(
                label: 'SIP Port',
                value: secondConnection.pbxSipPort.toString(),
              ),
              const SizedBox(height: 6),
              _InfoLine(
                label: 'Protocol',
                value: secondConnection.pbxSipProtocol,
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: widget.isCallable ? widget.onCall : null,
              icon: const Icon(Icons.call),
              label: const Text('Call'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: widget.isCallable ? Colors.green : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text('$label:', style: theme.textTheme.bodySmall),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
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

Color _shadowColor(Color color, double opacity) {
  return color.withAlpha((opacity * 255).round());
}

class _GeneralSettingsDialog extends StatelessWidget {
  const _GeneralSettingsDialog({required this.user});

  final PbxSipUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'SIP General settings',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Use these credentials to connect to any external SIP client',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            _InfoLine(label: 'SIP Username', value: user.sipLogin),
            const SizedBox(height: 6),
            _InfoLine(label: 'SIP Password', value: user.sipPassword),
            for (var i = 0; i < user.sipConnections.length && i < 2; i++) ...[
              const SizedBox(height: 6),
              _InfoLine(
                label: 'SIP Server',
                value: user.sipConnections[i].pbxSipUrl,
              ),
              const SizedBox(height: 6),
              _InfoLine(
                label: 'SIP Port',
                value: user.sipConnections[i].pbxSipPort.toString(),
              ),
              const SizedBox(height: 6),
              _InfoLine(
                label: 'Protocol',
                value: user.sipConnections[i].pbxSipProtocol,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
