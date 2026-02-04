import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/features/dongles/data/dongles_api.dart';
import 'package:app/features/dongles/models/dongle.dart';
import 'package:app/core/providers.dart';

final donglesApiProvider = Provider<DonglesApi>((ref) {
  return DonglesApi(ref.read(apiClientProvider));
});

final dongleListProvider = FutureProvider<List<Dongle>>((ref) async {
  return ref.read(donglesApiProvider).fetchDongles();
});
