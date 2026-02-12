import 'package:app/features/calls/state/call_reconnect.dart';
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
      log(CallReconnectLog.reconnectSkipMissingUser(reason));
      return false;
    }
    try {
      log(CallReconnectLog.reconnectFired(reason));
      await ensureRegistered(reconnectUser);
      if (isDisposed()) return false;
      return true;
    } catch (error) {
      if (isDisposed()) return false;
      log(CallReconnectLog.reconnectFailed(error));
      return false;
    }
  }
}
