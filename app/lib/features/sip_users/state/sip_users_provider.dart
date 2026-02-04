import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/sip_users/data/sip_users_api.dart';
import 'package:app/features/sip_users/models/sip_users_state.dart';
import 'package:app/core/providers.dart';

final sipUsersApiProvider = Provider<SipUsersApi>((ref) {
  return SipUsersApi(ref.read(graphqlClientProvider));
});

final sipUsersProvider = FutureProvider<SipUsersState>((ref) async {
  return ref.read(sipUsersApiProvider).fetchSipUsersState();
});
