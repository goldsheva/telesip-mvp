import 'package:app/features/sip_users/models/json_type_utils.dart';

/// Mirrors the `/components/schemas/PbxSipUser` connection object from OpenAPI.
class PbxSipConnection {
  final String pbxSipUrl;
  final int pbxSipPort;
  final String pbxSipProtocol;

  const PbxSipConnection({
    required this.pbxSipUrl,
    required this.pbxSipPort,
    required this.pbxSipProtocol,
  });

  factory PbxSipConnection.fromJson(Map<String, dynamic> json) {
    return PbxSipConnection(
      pbxSipUrl: parseOpenApiString(json['pbx_sip_url']),
      pbxSipPort: parseOpenApiInt(json['pbx_sip_port']),
      pbxSipProtocol: parseOpenApiString(json['pbx_sip_protocol']),
    );
  }
}
