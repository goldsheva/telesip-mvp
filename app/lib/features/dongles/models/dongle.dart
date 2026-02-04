import 'package:app/features/sip_users/models/json_type_utils.dart';

class Dongle {
  final int dongleId;
  final String name;
  final String? number;
  final bool isActive;
  final DongleOnlineStatus dongleOnlineStatus;
  final String displayStatus;
  final bool isTariffPackageActive;
  final DongleCallType? dongleCallType;

  const Dongle({
    required this.dongleId,
    required this.name,
    required this.number,
    required this.isActive,
    required this.dongleOnlineStatus,
    required this.displayStatus,
    required this.isTariffPackageActive,
    required this.dongleCallType,
  });

  factory Dongle.fromJson(Map<String, dynamic> json) {
    return Dongle(
      dongleId: parseOpenApiInt(json['dongle_id']),
      name: parseOpenApiString(json['name']),
      number: json['number'] as String?,
      isActive: json['is_active'] == true,
      dongleOnlineStatus: DongleOnlineStatus.fromValue(
        parseOpenApiInt(json['dongle_online_status']),
      ),
      displayStatus: parseOpenApiString(json['display_status']),
      isTariffPackageActive: json['is_tariff_package_active'] == true,
      dongleCallType: DongleCallType.fromValue(
        parseOpenApiNullableInt(json['dongle_call_type_id']),
      ),
    );
  }

  bool get isCallable => dongleOnlineStatus == DongleOnlineStatus.online;
}

enum DongleOnlineStatus {
  offline(1),
  onlineProcessing(2),
  error(3),
  manualPhoneDetermination(4),
  online(5),
  unknown(0);

  final int value;
  const DongleOnlineStatus(this.value);

  static DongleOnlineStatus fromValue(int? value) {
    switch (value) {
      case 1:
        return DongleOnlineStatus.offline;
      case 2:
        return DongleOnlineStatus.onlineProcessing;
      case 3:
        return DongleOnlineStatus.error;
      case 4:
        return DongleOnlineStatus.manualPhoneDetermination;
      case 5:
        return DongleOnlineStatus.online;
      default:
        return DongleOnlineStatus.unknown;
    }
  }
}

enum DongleCallType {
  sip(1),
  scenario(2);

  final int value;
  const DongleCallType(this.value);

  static DongleCallType? fromValue(int? value) {
    switch (value) {
      case 1:
        return DongleCallType.sip;
      case 2:
        return DongleCallType.scenario;
      default:
        return null;
    }
  }
}
