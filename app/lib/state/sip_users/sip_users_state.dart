import 'package:app/models/sip_user.dart';

class SipUsersState {
  final int total;
  final List<SipUser> items;

  const SipUsersState({required this.total, required this.items});
}
