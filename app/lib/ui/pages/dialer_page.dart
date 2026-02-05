import 'dart:async';

import 'package:call_audio_route/call_audio_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';
import 'package:flutter_native_contact_picker/model/contact.dart';

import 'package:app/features/calls/call_watchdog.dart';
import 'package:app/features/calls/state/call_notifier.dart';
import 'package:app/features/sip_users/models/pbx_sip_user.dart';

class DialerPage extends ConsumerStatefulWidget {
  const DialerPage({
    super.key,
    this.sipUser,
    this.dongleName,
    this.dongleNumber,
  });

  final PbxSipUser? sipUser;
  final String? dongleName;
  final String? dongleNumber;

  @override
  ConsumerState<DialerPage> createState() => _DialerPageState();
}

class _DialerPageState extends ConsumerState<DialerPage> {
  final _numberController = TextEditingController();
  final _contactPicker = FlutterNativeContactPicker();

  bool _isMuted = false;
  bool _isSpeakerOn = false;
  ProviderSubscription<CallState>? _stateSubscription;
  final CallAudioRoute _callAudioRoute = CallAudioRoute();
  AudioRouteInfo? _routeInfo;
  StreamSubscription<AudioRouteInfo>? _routeSubscription;
  bool _isBluetoothPreferred = false;
  bool _callAudioActive = false;
  bool _awaitingBluetoothConfirmation = false;
  Timer? _bluetoothConfirmTimer;

  String _effectiveRouteLabel() {
    final route = _routeInfo?.current;
    if (route != null) return _routeLabel(route);
    if (_isBluetoothPreferred) return 'Bluetooth';
    return _isSpeakerOn ? 'Speaker' : 'Handset';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _registerSipUser());
    _routeSubscription = _callAudioRoute.routeChanges.listen(_onRouteInfo);
    _callAudioRoute.getRouteInfo().then((info) {
      if (!mounted) return;
      setState(() {
        _routeInfo = info as AudioRouteInfo?;
      });
    });

    _stateSubscription = ref.listenManual<CallState>(callControllerProvider, (
      previous,
      next,
    ) {
      _handleCallStateChange(previous, next);
      final message = next.errorMessage;
      if (message != null &&
          message.isNotEmpty &&
          message != previous?.errorMessage) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    });
  }

  @override
  void dispose() {
    _routeSubscription?.cancel();
    _bluetoothConfirmTimer?.cancel();
    if (_callAudioActive) {
      _callAudioActive = false;
      Future.microtask(() async {
        try {
          await _callAudioRoute.setRoute(AudioRoute.systemDefault);
        } catch (_) {
          // best-effort
        }
        try {
          await _callAudioRoute.stopCallAudio();
        } catch (_) {
          // best-effort
        }
      });
    }
    _stateSubscription?.close();
    _numberController.dispose();
    super.dispose();
  }

  Future<void> _call() async {
    final raw = _numberController.text;
    final number = _normalizeNumber(raw);
    if (number.isEmpty) return;
    if (number != raw) {
      _numberController.text = number;
      _numberController.selection = TextSelection.fromPosition(
        TextPosition(offset: number.length),
      );
    }
    await ref.read(callControllerProvider.notifier).startCall(number);
  }

  static String _normalizeNumber(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return trimmed;
    if (trimmed.startsWith('+')) return trimmed;
    return '+$trimmed';
  }

  Future<void> _pickContact() async {
    try {
      final Contact? contact = await _contactPicker.selectPhoneNumber();
      final number = contact?.selectedPhoneNumber?.trim();
      if (number == null || number.isEmpty) return;

      _numberController.text = number;
      _numberController.selection = TextSelection.fromPosition(
        TextPosition(offset: number.length),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to select contact: $error')),
      );
    }
  }

  Future<void> _openKeypad(CallInfo active) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _InCallKeypadSheet(
        title: active.destination,
        statusText: _status(active.status),
        onKey: (k) =>
            ref.read(callControllerProvider.notifier).sendDtmf(active.id, k),
      ),
    );
  }

  void _registerSipUser() {
    final user = widget.sipUser;
    if (user == null) return;
    ref.read(callControllerProvider.notifier).ensureRegistered(user);
  }

  void _handleCallStateChange(CallState? previous, CallState next) {
    Future.microtask(() async {
      final hadActive = previous?.activeCall != null;
      final hasActive = next.activeCall != null;

      if (hasActive && !hadActive) {
        await _startCallAudio();
      } else if (!hasActive && hadActive) {
        await _stopCallAudio();
      }

      final nextActive = next.activeCall;
      if (nextActive != null &&
          nextActive.status == CallStatus.connected &&
          _isBluetoothPreferred) {
        if (_routeInfo?.bluetoothConnected ?? false) {
          _awaitingBluetoothConfirmation = false;
          _bluetoothConfirmTimer?.cancel();
        } else {
          _awaitBluetoothConnection();
        }
      }
    });
  }

  Future<void> _startCallAudio() async {
    _callAudioActive = true;
    await _callAudioRoute.configureForCall();
    await _applyPreferredRoute();
  }

  Future<void> _stopCallAudio() async {
    _callAudioActive = false;
    _awaitingBluetoothConfirmation = false;
    _bluetoothConfirmTimer?.cancel();
    await _callAudioRoute.stopCallAudio();
    await _callAudioRoute.setRoute(AudioRoute.systemDefault);
    if (!mounted) return;
    setState(() {
      _isSpeakerOn = false;
      _isBluetoothPreferred = false;
    });
  }

  void _awaitBluetoothConnection() {
    _bluetoothConfirmTimer?.cancel();
    _awaitingBluetoothConfirmation = true;
    _bluetoothConfirmTimer = Timer(
      const Duration(milliseconds: 1500),
      () async {
        if (!_awaitingBluetoothConfirmation) return;
        _awaitingBluetoothConfirmation = false;
        await _callAudioRoute.setRoute(AudioRoute.earpiece);
        if (!mounted) return;
        setState(() {
          _isBluetoothPreferred = false;
          _isSpeakerOn = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bluetooth failed to connect, switching to handset'),
          ),
        );
      },
    );
  }

  void _onRouteInfo(AudioRouteInfo info) {
    final wasConnected = _routeInfo?.bluetoothConnected ?? false;
    setState(() {
      _routeInfo = info;
      _isSpeakerOn = info.current == AudioRoute.speaker;
    });
    if (wasConnected && !info.bluetoothConnected) {
      _showBluetoothDisconnectSnackBar();
    }
    if (_awaitingBluetoothConfirmation && info.bluetoothConnected) {
      _awaitingBluetoothConfirmation = false;
      _bluetoothConfirmTimer?.cancel();
    }
  }

  void _showBluetoothDisconnectSnackBar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bluetooth headset disconnected')),
    );
  }

  String _routeLabel(AudioRoute route) {
    switch (route) {
      case AudioRoute.earpiece:
        return 'Handset';
      case AudioRoute.speaker:
        return 'Speaker';
      case AudioRoute.bluetooth:
        return 'Bluetooth';
      case AudioRoute.wiredHeadset:
        return 'Wired headset';
      case AudioRoute.systemDefault:
        return 'System default';
    }
  }

  Future<void> _toggleSpeaker() async {
    final enabling = !_isSpeakerOn;
    setState(() {
      _isSpeakerOn = enabling;
      if (enabling) {
        _isBluetoothPreferred = false;
      }
    });
    await _callAudioRoute.setRoute(
      enabling ? AudioRoute.speaker : AudioRoute.earpiece,
    );
    if (!mounted) return;
    setState(() {
      _isSpeakerOn = enabling;
    });
  }

  Future<void> _toggleBluetooth() async {
    final enabling = !_isBluetoothPreferred;
    setState(() {
      _isBluetoothPreferred = enabling;
      if (enabling) {
        _isSpeakerOn = false;
      }
    });
    _awaitingBluetoothConfirmation = false;
    _bluetoothConfirmTimer?.cancel();
    await _callAudioRoute.setRoute(
      enabling ? AudioRoute.bluetooth : AudioRoute.earpiece,
    );
    if (!mounted) return;
    if (!enabling) {
      setState(() => _isSpeakerOn = false);
    }
  }

  Future<void> _applyPreferredRoute() async {
    final route = _isBluetoothPreferred
        ? AudioRoute.bluetooth
        : (_isSpeakerOn ? AudioRoute.speaker : AudioRoute.earpiece);
    await _callAudioRoute.setRoute(route);
    if (!mounted) return;
    setState(() {
      _isSpeakerOn = route == AudioRoute.speaker;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(callControllerProvider);
    final notifier = ref.read(callControllerProvider.notifier);

    final rawActiveCall = state.activeCall;
    final dongleId = widget.sipUser?.dongleId;
    final active = dongleId == null || rawActiveCall?.dongleId == dongleId
        ? rawActiveCall
        : null;
    final hasActiveCall = active != null && active.status != CallStatus.ended;
    final watchdogState = state.watchdogState;
    final history = dongleId == null
        ? state.history
        : state.history.where((call) => call.dongleId == dongleId).toList();

    final titleText = widget.dongleName ?? widget.sipUser?.sipLogin ?? 'Dialer';
    final subtitle = widget.dongleNumber;
    final theme = Theme.of(context);

    return PopScope(
      canPop: !hasActiveCall,
      onPopInvokedWithResult: (didPop, _) {
        if (hasActiveCall && !didPop) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please finish the call first')),
          );
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          elevation: 0,
          title: _AppBarTitle(title: titleText, subtitle: subtitle),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Outgoing call',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Number field
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _NumberInputCard(
                      controller: _numberController,
                      onPickContact: _pickContact,
                      onClear: _numberController.clear,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Content
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                      children: [
                        if (active != null) ...[
                          _ActiveCallCard(
                            active: active,
                            isMuted: _isMuted,
                            isSpeakerOn: _isSpeakerOn,
                            onToggleMute: hasActiveCall
                                ? () {
                                    setState(() => _isMuted = !_isMuted);
                                  }
                                : null,
                            onToggleSpeaker: hasActiveCall
                                ? () {
                                    _toggleSpeaker();
                                  }
                                : null,
                            onOpenKeypad: hasActiveCall
                                ? () => _openKeypad(active)
                                : null,
                            onHangup: hasActiveCall
                                ? () => notifier.hangup(active.id)
                                : null,
                          ),
                          if (_routeInfo != null && hasActiveCall) ...[
                            const SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color.fromRGBO(0, 0, 0, 0.05),
                                    blurRadius: 18,
                                    offset: Offset(0, 10),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Route: ${_effectiveRouteLabel()}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                  if (_routeInfo!.available.contains(
                                    AudioRoute.bluetooth,
                                  ))
                                    Text(
                                      'Bluetooth: ${_routeInfo!.bluetoothConnected ? 'connected' : 'available'}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.grey),
                                    ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      _ControlButton(
                                        icon: Icons.volume_up,
                                        label: 'Speaker',
                                        active: _isSpeakerOn,
                                        onTap: () => _toggleSpeaker(),
                                      ),
                                      if (_routeInfo!.available.contains(
                                        AudioRoute.bluetooth,
                                      )) ...[
                                        const SizedBox(width: 8),
                                        _ControlButton(
                                          icon: Icons.bluetooth,
                                          label: 'Bluetooth',
                                          active:
                                              _isBluetoothPreferred ||
                                              _routeInfo!.current ==
                                                  AudioRoute.bluetooth,
                                          onTap: () => _toggleBluetooth(),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (watchdogState.status ==
                                      CallWatchdogStatus.reconnecting) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      watchdogState.message,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: Colors.orange),
                                    ),
                                  ],
                                  if (watchdogState.status ==
                                      CallWatchdogStatus.failed) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      watchdogState.message,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: Colors.redAccent),
                                    ),
                                    const SizedBox(height: 4),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: hasActiveCall
                                            ? () => notifier.retryCallAudio()
                                            : null,
                                        child: const Text('Retry audio'),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                        ],
                        if (history.isNotEmpty)
                          _HistorySection(history: history),
                      ],
                    ),
                  ),

                  // Call button
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _numberController,
                      builder: (context, value, _) {
                        final canCall =
                            value.text.trim().isNotEmpty &&
                            !hasActiveCall &&
                            state.isRegistered;
                        return SizedBox(
                          height: 56,
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: canCall ? _call : null,
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              backgroundColor: Colors.green,
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            child: const Text('Call'),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _status(CallStatus status) {
    switch (status) {
      case CallStatus.dialing:
        return 'Dialing';
      case CallStatus.ringing:
        return 'Ringing';
      case CallStatus.connected:
        return 'In call';
      case CallStatus.ended:
        return 'Ended';
    }
  }
}

class _AppBarTitle extends StatelessWidget {
  const _AppBarTitle({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        if (subtitle != null && subtitle.isNotEmpty)
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
      ],
    );
  }
}

class _NumberInputCard extends StatelessWidget {
  const _NumberInputCard({
    required this.controller,
    required this.onPickContact,
    required this.onClear,
  });

  final TextEditingController controller;
  final VoidCallback onPickContact;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.phone,
        autofocus: true,
        inputFormatters: [_PhoneNumberInputFormatter()],
        decoration: InputDecoration(
          hintText: 'Enter a number',
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          prefixIcon: const Icon(Icons.phone),
          suffixIcon: SizedBox(
            width: 96,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: onPickContact,
                  icon: const Icon(Icons.contacts),
                ),
                IconButton(onPressed: onClear, icon: const Icon(Icons.close)),
              ],
            ),
          ),
        ),
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _PhoneNumberInputFormatter extends TextInputFormatter {
  static final _digitMatcher = RegExp(r'\d');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final buffer = StringBuffer();
    var plusAllowed = true;
    for (var i = 0; i < newValue.text.length; i++) {
      final char = newValue.text[i];
      if (char == '+') {
        if (buffer.isEmpty && plusAllowed) {
          buffer.write(char);
          plusAllowed = false;
        }
        continue;
      }
      if (_digitMatcher.hasMatch(char)) {
        buffer.write(char);
        plusAllowed = false;
      }
    }
    final filtered = buffer.toString();
    return TextEditingValue(
      text: filtered,
      selection: TextSelection.collapsed(offset: filtered.length),
    );
  }
}

class _ActiveCallCard extends StatelessWidget {
  const _ActiveCallCard({
    required this.active,
    required this.isMuted,
    required this.isSpeakerOn,
    required this.onToggleMute,
    required this.onToggleSpeaker,
    required this.onOpenKeypad,
    required this.onHangup,
  });

  final CallInfo active;
  final bool isMuted;
  final bool isSpeakerOn;

  final VoidCallback? onToggleMute;
  final VoidCallback? onToggleSpeaker;
  final VoidCallback? onOpenKeypad;
  final VoidCallback? onHangup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final events = active.timeline.reversed.take(8).toList();

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.05),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Active call · ${_status(active.status)}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(active.destination, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),

          if (events.isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text('Details'),
              children: [
                for (final e in events)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $e', style: theme.textTheme.bodySmall),
                  ),
              ],
            ),

          const SizedBox(height: 8),

          Row(
            children: [
              _ControlButton(
                icon: Icons.mic_off,
                label: 'Mute',
                active: isMuted,
                onTap: onToggleMute,
              ),
              _ControlButton(
                icon: Icons.volume_up,
                label: 'Speaker',
                active: isSpeakerOn,
                onTap: onToggleSpeaker,
              ),
              _ControlButton(
                icon: Icons.dialpad,
                label: 'Keypad',
                onTap: onOpenKeypad,
              ),
              _ControlButton(
                icon: Icons.call_end,
                label: 'Hang up',
                danger: true,
                onTap: onHangup,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _status(CallStatus status) {
    switch (status) {
      case CallStatus.dialing:
        return 'Dialing';
      case CallStatus.ringing:
        return 'Ringing';
      case CallStatus.connected:
        return 'In call';
      case CallStatus.ended:
        return 'Ended';
    }
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    this.active = false,
    this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = Colors.green;
    final enabled = onTap != null;

    final borderColor = danger
        ? Colors.redAccent
        : (active
              ? accent
              : theme.colorScheme.onSurface.withValues(
                  alpha: (0.2 * 255).roundToDouble(),
                ));
    final iconColor = danger
        ? Colors.redAccent
        : (active ? accent : theme.iconTheme.color ?? Colors.black87);
    final bgColor = Colors.transparent;

    final disabledColor = theme.disabledColor;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: enabled ? bgColor : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: enabled ? borderColor : disabledColor),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: enabled ? iconColor : disabledColor),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: enabled ? iconColor : disabledColor,
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

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.history});

  final List<CallInfo> history;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: const Text('Call history'),
      childrenPadding: EdgeInsets.zero,
      tilePadding: EdgeInsets.zero,
      children: history.map((call) {
        return ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          tileColor: Theme.of(context).colorScheme.surface,
          title: Text(call.destination),
          subtitle: Text(_status(call.status)),
          trailing: Text(
            '${call.createdAt.hour.toString().padLeft(2, '0')}:${call.createdAt.minute.toString().padLeft(2, '0')}',
          ),
        );
      }).toList(),
    );
  }

  static String _status(CallStatus status) {
    switch (status) {
      case CallStatus.dialing:
        return 'Dialing';
      case CallStatus.ringing:
        return 'Ringing';
      case CallStatus.connected:
        return 'In call';
      case CallStatus.ended:
        return 'Ended';
    }
  }
}

/// ------------------------------
/// "Phone-style": sheet with top section (number/status) + responsive keypad
/// ------------------------------
class _InCallKeypadSheet extends StatefulWidget {
  const _InCallKeypadSheet({
    required this.title,
    required this.statusText,
    required this.onKey,
  });

  final String title;
  final String statusText;
  final Future<void> Function(String key) onKey;

  @override
  State<_InCallKeypadSheet> createState() => _InCallKeypadSheetState();
}

class _InCallKeypadSheetState extends State<_InCallKeypadSheet> {
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

  String _sequence = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: LayoutBuilder(
          builder: (context, c) {
            const cols = 3;
            const cross = 12.0;
            const main = 12.0;
            const rows = 4;

            final cellW = (c.maxWidth - cross * (cols - 1)) / cols;

            // Height of the header section (handle + number + status + paddings)
            final headerH = 4 + 10 + 12 + 22 + 8 + 18 + 12; // approximate
            final dtmfH = _sequence.isNotEmpty ? (18 + 10) : 0;

            final availableForGrid = (c.maxHeight - headerH - dtmfH).clamp(
              220.0,
              c.maxHeight,
            );

            final cellH = ((availableForGrid - main * (rows - 1)) / rows).clamp(
              56.0,
              cellW * 1.05,
            );

            final aspect = cellW / cellH;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 10),

                // Top like a phone: number + status
                Text(
                  widget.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.statusText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),

                if (_sequence.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'DTMF: $_sequence',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _keys.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: cross,
                    mainAxisSpacing: main,
                    childAspectRatio: aspect,
                  ),
                  itemBuilder: (context, i) {
                    final key = _keys[i];
                    return _KeypadButton(
                      label: key,
                      onTap: () async {
                        await widget.onKey(key);
                        if (!mounted) return;
                        setState(() {
                          if (_sequence.length < 32) _sequence += key;
                        });
                      },
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final fontSize = (screenW / 14).clamp(18.0, 26.0);

    return Material(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}
