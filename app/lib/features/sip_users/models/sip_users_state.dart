import 'package:app/features/sip_users/models/pbx_sip_user.dart';

class SipUsersState {
  final int total;
  final List<PbxSipUser> items;

  const SipUsersState({required this.total, required this.items});

  static PbxSipUser itemFromJson(Map<String, dynamic> json) {
    return PbxSipUser.fromJson(json);
  }
}
