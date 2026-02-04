import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/dongles/data/dongles_api.dart';
import 'package:app/features/dongles/models/dongle.dart';
import 'package:app/core/providers.dart';

final donglesApiProvider = Provider<DonglesApi>((ref) {
  return DonglesApi(ref.read(apiClientProvider));
});

final donglesProvider = AsyncNotifierProvider<DonglesNotifier, List<Dongle>>(
  DonglesNotifier.new,
);

class DonglesNotifier extends AsyncNotifier<List<Dongle>> {
  @override
  Future<List<Dongle>> build() async {
    return _fetch();
  }

  Future<List<Dongle>> _fetch() async {
    final api = ref.read(donglesApiProvider);
    return api.fetchDongles();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }
}
