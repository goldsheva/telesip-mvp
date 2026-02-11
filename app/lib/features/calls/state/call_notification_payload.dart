class PendingCallAction {
  const PendingCallAction({this.callId});

  final String? callId;

  static PendingCallAction? tryParse(Map? raw) {
    if (raw == null) return null;
    final callId = raw['call_id']?.toString() ?? raw['callId']?.toString();
    return PendingCallAction(callId: callId);
  }
}

class PendingIncomingHint {
  const PendingIncomingHint({
    this.callId,
    this.callUuid,
    this.from,
    this.displayName,
  });

  final String? callId;
  final String? callUuid;
  final String? from;
  final String? displayName;

  static PendingIncomingHint? tryParse(Map? raw) {
    if (raw == null) return null;
    final payload = raw['payload'];
    if (payload is! Map<String, dynamic>) return null;
    final rawFrom = payload['from'];
    if (rawFrom == null) return null;
    final from = rawFrom.toString().trim();
    if (from.isEmpty) return null;
    final rawDisplayName = payload['display_name'];
    final trimmedDisplayName = rawDisplayName?.toString().trim();
    final displayName =
        trimmedDisplayName != null && trimmedDisplayName.isNotEmpty
        ? trimmedDisplayName
        : null;
    final callId = payload['call_id']?.toString();
    final callUuid = payload['call_uuid']?.toString();
    return PendingIncomingHint(
      callId: callId,
      callUuid: callUuid,
      from: from,
      displayName: displayName,
    );
  }
}
