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
  final _dtmfController = TextEditingController();
  final FlutterNativeContactPicker _contactPicker =
      FlutterNativeContactPicker();

  @override
  void dispose() {
    _numberController.dispose();
    _dtmfController.dispose();
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

  Future<void> _sendDtmf(String callId) async {
    final digits = _dtmfController.text.trim();
    if (digits.isEmpty) {
      _showMessage('Введите цифры DTMF');
      return;
    }

    await ref.read(callControllerProvider.notifier).sendDtmf(callId, digits);
    _dtmfController.clear();
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
          children: [
            const SizedBox(height: 10),
            Text(
              'Исходящий звонок',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade400),
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
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (active != null) ...[
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
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Активный вызов · ${_describeStatus(active.status)}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Номер: ${active.destination}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 8),
                              if (active.timeline.isNotEmpty) ...[
                                Text(
                                  'События:',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 6),
                                ...active.timeline.reversed.map(
                                  (event) => Text(
                                    '• $event',
                                    maxLines: 2,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ),
                                const SizedBox(height: 10),
                              ],
                              TextField(
                                controller: _dtmfController,
                                decoration: const InputDecoration(
                                  labelText: 'DTMF',
                                  hintText: '123#',
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () => _sendDtmf(active.id),
                                      child: const Text('Отправить DTMF'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton.icon(
                                    onPressed: () => notifier.hangup(active.id),
                                    icon: const Icon(Icons.call_end),
                                    label: const Text('Сбросить'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (state.history.isNotEmpty) ...[
                        Text(
                          'История звонков',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 12),
                        ...state.history.map(
                          (call) => ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            tileColor: Theme.of(context).colorScheme.surface,
                            title: Text(call.destination),
                            subtitle: Text(_describeStatus(call.status)),
                            trailing: Text(
                              '${call.createdAt.hour.toString().padLeft(2, '0')}:${call.createdAt.minute.toString().padLeft(2, '0')}',
                            ),
                          ),
                        ),
                      ],
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
                  onPressed: active != null ? null : _call,
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
