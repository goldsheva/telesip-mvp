import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';
import 'package:flutter_native_contact_picker/model/contact.dart';

import 'package:app/features/calls/state/call_notifier.dart';
import 'package:app/features/sip_users/models/pbx_sip_user.dart';
import 'package:app/services/permissions_service.dart';

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
  int? _lastOutgoingUserId;
  late final ProviderSubscription<CallState> _callStateSubscription;

  @override
  void dispose() {
    _numberController.dispose();
    _callStateSubscription.close();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _callStateSubscription = ref.listenManual<CallState>(
      callControllerProvider,
      (previous, next) {
        final message = next.errorMessage;
        if (message != null &&
            message.isNotEmpty &&
            message != previous?.errorMessage) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      },
    );
    _scheduleOutgoingUser(widget.sipUser);
  }

  @override
  void didUpdateWidget(covariant DialerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sipUser?.pbxSipUserId != oldWidget.sipUser?.pbxSipUserId) {
      _scheduleOutgoingUser(widget.sipUser);
    }
  }

  void _scheduleOutgoingUser(PbxSipUser? user) {
    if (user == null || user.pbxSipUserId == _lastOutgoingUserId) {
      return;
    }
    _lastOutgoingUserId = user.pbxSipUserId;
    Future.microtask(() {
      unawaited(
        ref.read(callControllerProvider.notifier).setOutgoingSipUser(user),
      );
    });
  }

  Future<void> _call() async {
    debugPrint(
      '[CALLS_UI] _call() entered mounted=$mounted raw=${_numberController.text}',
    );
    final raw = _numberController.text;
    final number = _normalizeNumber(raw);
    if (number.isEmpty) {
      debugPrint(
        '[CALLS_UI] dial skip reason=empty number=$number mounted=$mounted',
      );
      return;
    }
    if (number != raw) {
      _numberController.text = number;
      _numberController.selection = TextSelection.fromPosition(
        TextPosition(offset: number.length),
      );
    }
    final hasMic = await PermissionsService.ensureMicrophonePermission();
    if (!hasMic) {
      debugPrint(
        '[CALLS_UI] dial skip reason=mic-permission number=$number mounted=$mounted',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone permission is required to make calls'),
        ),
      );
      return;
    }
    debugPrint('[CALLS_UI] dial pressed number=$number mounted=$mounted');
    await ref.read(callControllerProvider.notifier).startCall(number);
    debugPrint('[CALLS_UI] dial dispatched number=$number');
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(callControllerProvider);
    final rawActiveCall = state.activeCall;
    final dongleId = widget.sipUser?.dongleId;
    final effectiveActive = dongleId == null
        ? rawActiveCall
        : (rawActiveCall != null && rawActiveCall.dongleId == dongleId
              ? rawActiveCall
              : null);
    final hasActiveCall =
        effectiveActive != null && effectiveActive.status != CallStatus.ended;
    final statusText = hasActiveCall ? _status(effectiveActive.status) : null;

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
        backgroundColor: theme.colorScheme.surface,
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
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _NumberInputCard(
                      controller: _numberController,
                      onPickContact: _pickContact,
                      onClear: _numberController.clear,
                    ),
                  ),

                  if (statusText != null) ...[
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Call in progress: $statusText',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],

                  const Spacer(),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _numberController,
                      builder: (context, value, _) {
                        final rawInput = value.text;
                        final notifier = ref.read(
                          callControllerProvider.notifier,
                        );
                        final canCall = notifier.canStartOutgoingCallUi(
                          state,
                          rawInput,
                        );
                        return SizedBox(
                          height: 56,
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: canCall ? _call : null,
                            icon: const Icon(Icons.call),
                            label: const Text('Call'),
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
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
