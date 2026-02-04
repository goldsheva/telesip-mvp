import 'package:app/features/sip_users/models/json_type_utils.dart';

class Dongle {
  final int dongleId;
  final String name;
  final String? number;
  final bool isActive;
  final String dongleOnlineStatus;
  final String displayStatus;

  const Dongle({
    required this.dongleId,
    required this.name,
    required this.number,
    required this.isActive,
    required this.dongleOnlineStatus,
    required this.displayStatus,
  });

  factory Dongle.fromJson(Map<String, dynamic> json) {
    return Dongle(
      dongleId: parseOpenApiInt(json['dongle_id']),
      name: parseOpenApiString(json['name']),
      number: json['number'] as String?,
      isActive: json['is_active'] == true,
      dongleOnlineStatus: parseOpenApiString(json['dongle_online_status']),
      displayStatus: parseOpenApiString(json['display_status']),
    );
  }

  bool get isCallable =>
      displayStatus == 'ACTIVE' && dongleOnlineStatus == 'ONLINE';
}
