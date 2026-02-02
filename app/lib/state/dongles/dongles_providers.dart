import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/models/dongle.dart';
import 'package:app/services/dongles_api.dart';
import 'package:app/state/providers.dart';

final donglesApiProvider = Provider<DonglesApi>((ref) {
  return DonglesApi(ref.read(apiClientProvider));
});

final dongleListProvider = FutureProvider<List<Dongle>>((ref) async {
  return ref.read(donglesApiProvider).fetchDongles();
});
