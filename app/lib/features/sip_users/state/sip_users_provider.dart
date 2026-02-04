import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/sip_users/data/sip_users_api.dart';
import 'package:app/features/sip_users/models/sip_users_state.dart';
import 'package:app/core/providers.dart';

final sipUsersApiProvider = Provider<SipUsersApi>((ref) {
  return SipUsersApi(ref.read(apiClientProvider));
});

final sipUsersProvider = AsyncNotifierProvider<SipUsersNotifier, SipUsersState>(
  SipUsersNotifier.new,
);

class SipUsersNotifier extends AsyncNotifier<SipUsersState> {
  @override
  Future<SipUsersState> build() async {
    return _fetch();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<SipUsersState> _fetch() async {
    final api = ref.read(sipUsersApiProvider);
    return api.fetchSipUsersState();
  }
}
