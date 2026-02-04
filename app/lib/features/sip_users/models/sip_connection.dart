class SipConnection {
  final String sipUrl;
  final int sipPort;
  final String sipProtocol;

  const SipConnection({
    required this.sipUrl,
    required this.sipPort,
    required this.sipProtocol,
  });

  factory SipConnection.fromJson(Map<String, dynamic> json) {
    return SipConnection(
      sipUrl: (json['sipUrl'] as String?) ?? '',
      sipPort: (json['sipPort'] as num?)?.toInt() ?? 0,
      sipProtocol: (json['sipProtocol'] as String?) ?? '',
    );
  }
}
