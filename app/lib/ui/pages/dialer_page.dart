import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';
import 'package:flutter_native_contact_picker/model/contact.dart';

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
  final FlutterNativeContactPicker _contactPicker =
      FlutterNativeContactPicker();
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  static const List<String> _keypadKeys = [
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
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  Future<void> _call() async {
    final number = _numberController.text.trim();
    if (number.isEmpty) {
      _showMessage('Введите номер');
      return;
    }

    await ref.read(callControllerProvider.notifier).startCall(number);
  }

  Future<void> _sendDtmfDigits(String callId, String digits) async {
    final trimmed = digits.trim();
    if (trimmed.isEmpty) return;
    await ref.read(callControllerProvider.notifier).sendDtmf(callId, trimmed);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(callControllerProvider);
    final notifier = ref.read(callControllerProvider.notifier);
    final active = state.activeCall;
    final hasActiveCall =
        active != null && active.status != CallStatus.ended;
    final sipUser = widget.sipUser;

    final titleText = widget.dongleName ?? sipUser?.sipLogin ?? 'Набор';
    final subtitle = widget.dongleNumber;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              titleText,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (subtitle != null && subtitle.isNotEmpty)
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Исходящий звонок',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade400),
              ),
            ),
            const SizedBox(height: 30),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
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
                  controller: _numberController,
                  keyboardType: TextInputType.phone,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Введите номер',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                    prefixIcon: const Icon(Icons.phone),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: _pickContact,
                          icon: const Icon(Icons.contacts),
                        ),
                        IconButton(
                          onPressed: () {
                            _numberController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (active != null) ...[
                        _buildActiveCallSection(active, notifier),
                        const SizedBox(height: 24),
                      ],
                      if (state.history.isNotEmpty)
                        _buildHistorySection(state.history),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                height: 56,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: hasActiveCall ? null : _call,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    backgroundColor: Colors.green,
                    textStyle: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Позвонить'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showKeypad(CallInfo active) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        var sequence = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
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
                  const SizedBox(height: 12),
                  if (sequence.isNotEmpty)
                    Text(
                      'DTMF: $sequence',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  if (sequence.isNotEmpty) const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.1,
                    children: _keypadKeys.map((key) {
                      return ElevatedButton(
                        onPressed: () async {
                          await _sendDtmfDigits(active.id, key);
                          setSheetState(() {
                            sequence += key;
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          backgroundColor: Colors.grey.shade200,
                          foregroundColor: Colors.black87,
                          textStyle: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                          elevation: 0,
                        ),
                        child: Text(key),
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActiveCallSection(CallInfo active, CallNotifier notifier) {
    final theme = Theme.of(context);
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
            'Активный вызов · ${_describeStatus(active.status)}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Номер: ${active.destination}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          if (active.timeline.isNotEmpty) ...[
            Text('События:', style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            ...active.timeline.reversed.map(
              (event) => Text(
                '• $event',
                maxLines: 2,
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (active.status != CallStatus.ended)
            Row(
              children: [
                _buildControlButton(
                  icon: Icons.mic_off,
                  label: 'Mute',
                  active: _isMuted,
                  onTap: () => setState(() => _isMuted = !_isMuted),
                ),
                _buildControlButton(
                  icon: Icons.volume_up,
                  label: 'Speaker',
                  active: _isSpeakerOn,
                  onTap: () => setState(() => _isSpeakerOn = !_isSpeakerOn),
                ),
                _buildControlButton(
                  icon: Icons.dialpad,
                  label: 'Keypad',
                  onTap: () => _showKeypad(active),
                ),
                _buildControlButton(
                  icon: Icons.call_end,
                  label: 'Hang up',
                  onTap: () => notifier.hangup(active.id),
                  background: _applyOpacity(Colors.redAccent, 0.12),
                  borderColor: Colors.redAccent,
                  iconColor: Colors.redAccent,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildHistorySection(List<CallInfo> history) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExpansionTile(
          title: const Text('История звонков'),
          childrenPadding: EdgeInsets.zero,
          tilePadding: EdgeInsets.zero,
          children: history.map((call) {
            return ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              tileColor: Theme.of(context).colorScheme.surface,
              title: Text(call.destination),
              subtitle: Text(_describeStatus(call.status)),
              trailing: Text(
                '${call.createdAt.hour.toString().padLeft(2, '0')}:${call.createdAt.minute.toString().padLeft(2, '0')}',
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
    Color? background,
    Color? borderColor,
    Color? iconColor,
  }) {
    final theme = Theme.of(context);
    final accent = Colors.green;
    final resolvedBorder =
        borderColor ??
        (active ? accent : _applyOpacity(theme.colorScheme.onSurface, 0.2));
    final resolvedBackground =
        background ??
        (active ? _applyOpacity(accent, 0.12) : Colors.transparent);
    final resolvedIconColor =
        iconColor ?? (active ? accent : theme.iconTheme.color);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: resolvedIconColor,
    );

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: resolvedBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: resolvedBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: resolvedIconColor),
                const SizedBox(height: 4),
                Text(label, style: labelStyle),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _applyOpacity(Color color, double opacity) {
    return color.withAlpha((opacity * 255).round());
  }

  Future<void> _pickContact() async {
    try {
      final Contact? contact = await _contactPicker.selectPhoneNumber();
      final number = contact?.selectedPhoneNumber;
      if (number != null && number.isNotEmpty) {
        final trimmed = number.trim();
        _numberController.text = trimmed;
        _numberController.selection = TextSelection.fromPosition(
          TextPosition(offset: trimmed.length),
        );
        setState(() {});
      }
    } catch (error) {
      _showMessage('Не удалось выбрать контакт: $error');
    }
  }

  String _describeStatus(CallStatus status) {
    switch (status) {
      case CallStatus.dialing:
        return 'Идёт набор';
      case CallStatus.ringing:
        return 'Звонит';
      case CallStatus.connected:
        return 'В разговоре';
      case CallStatus.ended:
        return 'Завершён';
    }
  }
}
