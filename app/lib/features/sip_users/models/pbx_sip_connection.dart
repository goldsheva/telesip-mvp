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
      pbxSipUrl: json['pbx_sip_url'] as String? ?? '',
      pbxSipPort: (json['pbx_sip_port'] as num?)?.toInt() ?? 0,
      pbxSipProtocol: json['pbx_sip_protocol'] as String? ?? '',
    );
  }
}
