import 'package:app/features/sip_users/models/sip_connection.dart';

class SipUser {
  final int sipUserId;
  final int userId;

  final String sipLogin;
  final String sipPassword;

  final int dialplanId;
  final int? dongleId;

  final String? pbxSipUrl;
  final List<SipConnection> sipConnections;

  const SipUser({
    required this.sipUserId,
    required this.userId,
    required this.sipLogin,
    required this.sipPassword,
    required this.dialplanId,
    required this.dongleId,
    required this.pbxSipUrl,
    required this.sipConnections,
  });

  factory SipUser.fromJson(Map<String, dynamic> json) {
    final conns = json['sipConnections'];
    final list = (conns is List)
        ? conns
              .whereType<Map<String, dynamic>>()
              .map(SipConnection.fromJson)
              .toList()
        : const <SipConnection>[];

    return SipUser(
      sipUserId: (json['sipUserId'] as num?)?.toInt() ?? 0,
      userId: (json['userId'] as num?)?.toInt() ?? 0,
      sipLogin: (json['sipLogin'] as String?) ?? '',
      sipPassword: (json['sipPassword'] as String?) ?? '',
      dialplanId: (json['dialplanId'] as num?)?.toInt() ?? 0,
      dongleId: (json['dongleId'] as num?)?.toInt(),
      pbxSipUrl: json['pbxSipUrl'] as String?,
      sipConnections: list,
    );
  }
}
