import 'package:app/features/sip_users/models/sip_user.dart';

class SipUsersState {
  final int total;
  final List<SipUser> items;

  const SipUsersState({required this.total, required this.items});

  static SipUser itemFromJson(Map<String, dynamic> json) {
    return SipUser.fromJson(json);
  }
}
