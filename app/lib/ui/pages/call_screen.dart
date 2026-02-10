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
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(callControllerProvider);
    final call = state.calls[widget.callId];
    final isMuted = state.isMuted;
    final isSpeakerOn = state.audioRoute == AudioRoute.speaker;
    final activeCallId = state.activeCallId;
    if (call == null || call.status == CallStatus.ended) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).maybePop();
        }
      });
      return const Scaffold(body: SizedBox.shrink());
    }
    if (activeCallId != null &&
        activeCallId != widget.callId &&
        call.status != CallStatus.ringing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).maybePop();
        }
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    final notifier = ref.read(callControllerProvider.notifier);
    final statusText = _statusText(call.status);
    final isRinging = call.status == CallStatus.ringing;
    final title = call.status == CallStatus.ringing
        ? 'Incoming call'
        : call.status == CallStatus.dialing
        ? 'Calling…'
        : 'Call';

    return Scaffold(
      backgroundColor: Colors.grey.shade900,
      body: SafeArea(
        child: Padding(
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
              const Spacer(),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildToggle(
                      context,
                      icon: Icons.mic_off,
                      label: isMuted ? 'Unmute' : 'Mute',
                      active: isMuted,
                      onPressed: () => notifier.setCallMuted(!isMuted),
                    ),
                    _buildToggle(
                      context,
                      icon: Icons.volume_up,
                      label: isSpeakerOn ? 'Speaker on' : 'Speaker off',
                      active: isSpeakerOn,
                      onPressed: () {
                        final desired = !isSpeakerOn;
                        notifier.setCallAudioRoute(
                          desired ? AudioRoute.speaker : AudioRoute.earpiece,
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _Keypad(onKey: (key) => notifier.sendDtmf(call.id, key)),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => notifier.hangup(call.id),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Hang up'),
                ),
              ],
              const Spacer(flex: 2),
            ],
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
    return Expanded(
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
