import 'package:app/features/dongles/models/dongle_bootstrap.dart';

class Dongle {
  final int dongleId;
  final String name;
  final String? number;
  final bool isActive;
  final DongleOnlineStatus dongleOnlineStatus;
  final bool isTariffPackageActive;
  final DongleCallType? dongleCallType;
  final DongleBootstrap? bootstrapDongle;

  const Dongle({
    required this.dongleId,
    required this.name,
    required this.number,
    required this.isActive,
    required this.dongleOnlineStatus,
    required this.isTariffPackageActive,
    required this.dongleCallType,
    required this.bootstrapDongle,
  });

  factory Dongle.fromJson(Map<String, dynamic> json) {
    return Dongle(
      dongleId: (json['dongle_id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? 'Dongle',
      number: json['number'] as String?,
      isActive: json['is_active'] == true,
      dongleOnlineStatus: DongleOnlineStatus.fromValue(
        (json['dongle_online_status'] as num?)?.toInt(),
      ),
      isTariffPackageActive: json['is_tariff_package_active'] == true,
      dongleCallType: DongleCallType.fromValue(
        (json['dongle_call_type_id'] as num?)?.toInt(),
      ),
      bootstrapDongle: json['bootstrap_dongle'] is Map<String, dynamic>
          ? DongleBootstrap.fromJson(
              json['bootstrap_dongle'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  bool get isCallable => dongleOnlineStatus == DongleOnlineStatus.online;

  String? get bootstrapPbxSipUser => bootstrapDongle?.pbxSipUser;
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
