import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/calls/state/call_notifier.dart';

class DialerPage extends ConsumerStatefulWidget {
  const DialerPage({super.key});

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

    return Scaffold(
      appBar: AppBar(title: const Text('Dialer')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _numberController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Номер',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _buildKeypad(),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: active != null ? null : _call,
              icon: const Icon(Icons.call),
              label: const Text('Позвонить'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 16),
            if (active != null) ...[
              Card(
                child: Padding(
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
                          (event) => Text('• $event', maxLines: 2),
                        ),
                        const SizedBox(height: 8),
                      ],
                      TextField(
                        controller: _dtmfController,
                        decoration: const InputDecoration(
                          labelText: 'DTMF',
                          hintText: '123#',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
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
              ),
              const SizedBox(height: 16),
            ],
            if (state.history.isNotEmpty) ...[
              Text(
                'История звонков',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              ...state.history.map(
                (call) => ListTile(
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
    );
  }

  Widget _buildKeypad() {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: keys.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.1,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final key = keys[index];
        return ElevatedButton(
          onPressed: () => _appendDigit(key),
          child: Text(key, style: const TextStyle(fontSize: 20)),
        );
      },
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
