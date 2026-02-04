import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/calls/state/call_notifier.dart';
import 'package:app/features/sip_users/models/pbx_sip_user.dart';

class DialerPage extends ConsumerStatefulWidget {
  const DialerPage({super.key, this.sipUser});

  final PbxSipUser? sipUser;

  @override
  ConsumerState<DialerPage> createState() => _DialerPageState();
}

class _DialerPageState extends ConsumerState<DialerPage> {
  final _numberController = TextEditingController();
  final _dtmfController = TextEditingController();

  @override
  void dispose() {
    _numberController.dispose();
    _dtmfController.dispose();
    super.dispose();
  }

  void _appendDigit(String digit) {
    _numberController
      ..text = '${_numberController.text}$digit'
      ..selection = TextSelection.fromPosition(
        TextPosition(offset: _numberController.text.length),
      );
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

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        elevation: 0,
        title: Text(
          sipUser != null ? 'Dialer · ${sipUser.sipLogin}' : 'Dialer',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _numberController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: 'Введите номер',
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    prefixIcon: const Icon(Icons.dialpad_outlined),
                    suffixIcon: IconButton(
                      onPressed: () {
                        _numberController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 24),
              _buildKeypad(),
              const SizedBox(height: 20),
              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: active != null ? null : _call,
                  icon: const Icon(Icons.call),
                  label: const Text('Позвонить'),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    backgroundColor: Colors.green,
                    textStyle: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              if (active != null) ...[
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
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
                            style: Theme.of(context).textTheme.bodySmall,
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
              ],
              if (state.history.isNotEmpty) ...[
                const SizedBox(height: 20),
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
    );
  }

  Widget _buildKeypad() {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.0,
      children: keys
          .map((key) => _DialerKey(
                label: key,
                onTap: () => _appendDigit(key),
              ))
          .toList(),
    );
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

class _DialerKey extends StatelessWidget {
  const _DialerKey({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: theme.textTheme.headlineMedium?.copyWith(color: Colors.white),
        elevation: 4,
        shadowColor: Colors.black26,
      ),
      child: Text(
        label,
        style: theme.textTheme.headlineMedium?.copyWith(
          color: Colors.white,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
