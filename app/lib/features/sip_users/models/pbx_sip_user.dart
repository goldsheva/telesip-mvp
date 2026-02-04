import 'package:app/features/sip_users/models/json_type_utils.dart';
import 'package:app/features/sip_users/models/pbx_sip_connection.dart';

/// Represents the OpenAPI `PbxSipUser` schema returned by `/sip-user`.
class PbxSipUser {
  final int pbxSipUserId;
  final int userId;
  final String sipLogin;
  final String sipPassword;
  final int dialplanId;
  final int? dongleId;
  final List<PbxSipConnection> pbxSipConnections;

  const PbxSipUser({
    required this.pbxSipUserId,
    required this.userId,
    required this.sipLogin,
    required this.sipPassword,
    required this.dialplanId,
    required this.dongleId,
    required this.pbxSipConnections,
  });

  factory PbxSipUser.fromJson(Map<String, dynamic> json) {
    final connections = (json['pbx_sip_connections'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(PbxSipConnection.fromJson)
            .toList() ??
        const <PbxSipConnection>[];

    return PbxSipUser(
      pbxSipUserId: parseOpenApiInt(json['pbx_sip_user_id']),
      userId: parseOpenApiInt(json['user_id']),
      sipLogin: parseOpenApiString(json['sip_login']),
      sipPassword: parseOpenApiString(json['sip_password']),
      dialplanId: parseOpenApiInt(json['dialplan_id']),
      dongleId: parseOpenApiNullableInt(json['dongle_id']),
      pbxSipConnections: connections,
    );
  }

  int get sipUserId => pbxSipUserId;
  List<PbxSipConnection> get sipConnections => pbxSipConnections;
}
