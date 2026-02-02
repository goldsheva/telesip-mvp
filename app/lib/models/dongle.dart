class Dongle {
  final int id;
  final String title;
  final String phone;

  final bool isOnline;
  final bool isEnabled;

  final String? wifiName;
  final String? wifiPassword;

  const Dongle({
    required this.id,
    required this.title,
    required this.phone,
    required this.isOnline,
    required this.isEnabled,
    this.wifiName,
    this.wifiPassword,
  });

  factory Dongle.fromJson(Map<String, dynamic> json) {
    return Dongle(
      id: (json['dongle_id'] as num?)?.toInt() ?? 0,
      title: (json['name'] as String?) ?? 'Dongle',
      phone: (json['number'] as String?) ?? '—',
      isOnline: (json['is_online'] as bool?) ?? false,
      isEnabled: (json['is_hotspot_enable'] as bool?) ?? true,
      wifiName: json['hotspot_name'] as String?,
      wifiPassword: json['hotspot_password'] as String?,
    );
  }
}
