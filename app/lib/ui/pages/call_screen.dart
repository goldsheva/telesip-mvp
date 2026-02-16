import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/calls/state/call_notifier.dart';
import 'package:app/services/audio_route_types.dart';

class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key, required this.callId});

  final String callId;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  bool _exiting = false;

  void _scheduleExit() {
    if (_exiting) return;
    _exiting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(callControllerProvider);
    final isMuted = state.isMuted;
    final isSpeakerOn = state.audioRoute == AudioRoute.speaker;
    final availableRoutes = state.availableAudioRoutes;
    final speakerAvailable = availableRoutes.contains(AudioRoute.speaker);
    final bluetoothAvailable = availableRoutes.contains(AudioRoute.bluetooth);
    final earpieceAvailable = availableRoutes.contains(AudioRoute.earpiece);
    final call = state.effectiveCall;
    if (call == null || call.status == CallStatus.ended) {
      if (!state.hasActiveCall) {
        _scheduleExit();
      }
      return const SizedBox.shrink();
    }

    final notifier = ref.read(callControllerProvider.notifier);
    final statusText = _statusText(call.status);
    final isRinging = call.status == CallStatus.ringing;
    final hasActiveCall = state.hasActiveCall;
    final title = call.status == CallStatus.ringing
        ? 'Incoming call'
        : call.status == CallStatus.dialing
        ? 'Calling…'
        : 'Call';

    return PopScope(
      canPop: !hasActiveCall,
      child: Scaffold(
        backgroundColor: Colors.grey.shade900,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  call.destination,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  statusText,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.lightBlueAccent,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  _routeLabel(state.audioRoute),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.white54),
                  textAlign: TextAlign.center,
                ),
                if (call.failureMessage != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    call.failureMessage!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 32),
                if (isRinging) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => notifier.decline(call.id),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.redAccent),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text(
                            'Decline',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => notifier.answer(call.id),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text('Answer'),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      _buildToggle(
                        context,
                        icon: Icons.mic_off,
                        label: isMuted ? 'Unmute' : 'Mute',
                        active: isMuted,
                        onPressed: () => notifier.setCallMuted(!isMuted),
                      ),
                      if (speakerAvailable)
                        _buildToggle(
                          context,
                          icon: Icons.volume_up,
                          label: isSpeakerOn ? 'Speaker on' : 'Speaker off',
                          active: isSpeakerOn,
                          onPressed: () {
                            final desired = !isSpeakerOn;
                            final fallbackRoute = earpieceAvailable
                                ? AudioRoute.earpiece
                                : AudioRoute.systemDefault;
                            notifier.setCallAudioRoute(
                              desired ? AudioRoute.speaker : fallbackRoute,
                            );
                          },
                        ),
                      if (bluetoothAvailable)
                        _buildToggle(
                          context,
                          icon: Icons.bluetooth,
                          label: state.audioRoute == AudioRoute.bluetooth
                              ? 'Bluetooth on'
                              : 'Bluetooth off',
                          active: state.audioRoute == AudioRoute.bluetooth,
                          onPressed: () {
                            final fallbackRoute = earpieceAvailable
                                ? AudioRoute.earpiece
                                : AudioRoute.systemDefault;
                            final isBluetoothOn =
                                state.audioRoute == AudioRoute.bluetooth;
                            notifier.setCallAudioRoute(
                              isBluetoothOn
                                  ? fallbackRoute
                                  : AudioRoute.bluetooth,
                            );
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _Keypad(onKey: (key) => notifier.sendDtmf(call.id, key)),
                ],
              ],
            ),
          ),
        ),
        bottomNavigationBar: isRinging
            ? null
            : SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () => notifier.hangup(call.id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                    ),
                    child: const Text('Hang up'),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildToggle(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 140,
      child: OutlinedButton.icon(
        icon: Icon(icon, color: active ? Colors.greenAccent : Colors.white),
        label: Text(
          label,
          style: TextStyle(color: active ? Colors.greenAccent : Colors.white),
        ),
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: active ? Colors.greenAccent : Colors.white54),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  String _statusText(CallStatus status) {
    switch (status) {
      case CallStatus.ringing:
        return 'Ringing';
      case CallStatus.dialing:
        return 'Calling…';
      case CallStatus.connected:
        return 'In call';
      case CallStatus.ended:
        return 'Ended';
    }
  }

  String _routeLabel(AudioRoute route) {
    switch (route) {
      case AudioRoute.speaker:
        return 'Speaker';
      case AudioRoute.earpiece:
        return 'Earpiece';
      case AudioRoute.bluetooth:
        return 'Bluetooth';
      case AudioRoute.wiredHeadset:
        return 'Wired';
      case AudioRoute.systemDefault:
        return 'System';
    }
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onKey});

  final void Function(String key) onKey;

  static const _keys = <String>[
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '*',
    '0',
    '#',
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.2,
      children: _keys.map((key) {
        return ElevatedButton(
          onPressed: () => onKey(key),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey.shade800,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(key, style: const TextStyle(fontSize: 24)),
        );
      }).toList(),
    );
  }
}
