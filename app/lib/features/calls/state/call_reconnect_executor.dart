import 'package:app/features/sip_users/models/pbx_sip_user.dart';

class CallReconnectExecutor {
  CallReconnectExecutor({required this.isDisposed, required this.log});

  final bool Function() isDisposed;
  final void Function(String message) log;

  Future<bool> reconnect({
    required String reason,
    required PbxSipUser? reconnectUser,
    required Future<void> Function(PbxSipUser user) ensureRegistered,
  }) async {
    if (isDisposed()) return false;
    if (reconnectUser == null) {
      log('[CALLS_CONN] reconnect skip reason=$reason missing_user');
      return false;
    }
    try {
      log('[CALLS_CONN] reconnect fired reason=$reason');
      await ensureRegistered(reconnectUser);
      if (isDisposed()) return false;
      return true;
    } catch (error) {
      if (isDisposed()) return false;
      log('[CALLS_CONN] reconnect failed: $error');
      return false;
    }
  }
}
