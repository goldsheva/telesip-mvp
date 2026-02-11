import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/core/storage/fcm_storage.dart';
import 'package:app/core/providers/storage_providers.dart';
import 'package:app/features/calls/state/call_notifier.dart';

final incomingWakeCoordinatorProvider = Provider<IncomingWakeCoordinator>((
  ref,
) {
  return IncomingWakeCoordinator(ref);
});

class IncomingWakeCoordinator {
  IncomingWakeCoordinator(this._ref);

  final Ref _ref;
  DateTime? _lastHandledTimestamp;

  Future<bool> checkPendingHint() async {
    final raw = await FcmStorage.readPendingIncomingHint();
    if (raw == null) return false;

    final payload = raw['payload'] as Map<String, dynamic>?;
    final timestampRaw = raw['timestamp'] as String?;
    final timestamp = DateTime.tryParse(timestampRaw ?? '');
    final callUuid = payload?['call_uuid']?.toString() ?? '<none>';

    if (payload == null || timestamp == null) {
      debugPrint(
        '[INCOMING] invalid pending hint (call_uuid=$callUuid), clearing',
      );
      await FcmStorage.clearPendingIncomingHint();
      return false;
    }

    final now = DateTime.now();
    if (now.difference(timestamp) > const Duration(seconds: 60)) {
      debugPrint(
        '[INCOMING] pending hint expired after ${now.difference(timestamp).inSeconds}s (call_uuid=$callUuid)',
      );
      await FcmStorage.clearPendingIncomingHint();
      return false;
    }

    if (_lastHandledTimestamp != null &&
        _lastHandledTimestamp!.isAtSameMomentAs(timestamp)) {
      return false;
    }

    final callNotifier = _ref.read(callControllerProvider.notifier);
    if (callNotifier.isBusy) {
      _lastHandledTimestamp = timestamp;
      debugPrint(
        '[INCOMING] busy when handling wake hint (call_uuid=$callUuid), skipping SIP register',
      );
      return false;
    }

    final snapshot = await _ref.read(sipAuthStorageProvider).readSnapshot();
    if (snapshot == null) {
      debugPrint(
        '[INCOMING] no stored SIP credentials to register (call_uuid=$callUuid)',
      );
      return false;
    }

    debugPrint(
      '[INCOMING] pending wake hint handled, registering SIP (call_uuid=$callUuid)',
    );
    final registered = await callNotifier.registerWithSnapshot(snapshot);
    if (registered) {
      _lastHandledTimestamp = timestamp;
      debugPrint(
        '[INCOMING] wake-hint handled and cleared (call_uuid=$callUuid)',
      );
      await FcmStorage.clearPendingIncomingHint();
      return true;
    }
    return false;
  }
}
