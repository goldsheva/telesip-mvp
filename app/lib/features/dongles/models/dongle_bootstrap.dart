/// Represents the subset of `/dongle` payload used for bootstrap metadata.
class DongleBootstrap {
  final String imeiManufacture;
  final String imeiFake;
  final String pbxSipUser;

  const DongleBootstrap({
    required this.imeiManufacture,
    required this.imeiFake,
    required this.pbxSipUser,
  });

  factory DongleBootstrap.fromJson(Map<String, dynamic> json) {
    return DongleBootstrap(
      imeiManufacture: json['imei_manufacture'] as String? ?? '',
      imeiFake: json['imei_fake'] as String? ?? '',
      pbxSipUser: json['pbx_sip_user'] as String? ?? '',
    );
  }
}
