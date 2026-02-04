import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/services/sip_users_api.dart';
import 'package:app/state/providers.dart';
import 'package:app/models/sip_user.dart';
import 'sip_users_state.dart';
import 'package:app/config/api_endpoints.dart';

final sipUsersApiProvider = Provider<SipUsersApi>((ref) {
  return SipUsersApi(ref.read(apiClientProvider));
});

final sipUsersProvider = FutureProvider<SipUsersState>((ref) async {
  // Хотим одним запросом получить и total, и список.
  final api = ref.read(sipUsersApiProvider);

  final response = await ref.read(apiClientProvider).get(ApiEndpoints.sipUsersList);

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception('SipUsers failed: ${response.statusCode} ${response.body}');
  }

  final decoded = jsonDecode(response.body);
  if (decoded is! Map<String, dynamic>) {
    throw Exception('Unexpected response: ${response.body}');
  }

  final data = decoded['data'];
  if (data is! Map<String, dynamic>) {
    throw Exception('Missing "data" object: ${response.body}');
  }

  final wrap = data['sipUsers'];
  if (wrap is! Map<String, dynamic>) {
    throw Exception('Missing "data.sipUsers" object: ${response.body}');
  }

  final total = (wrap['total'] as num?)?.toInt() ?? 0;

  final list = wrap['sipUsers'];
  if (list is! List) {
    throw Exception('Missing "data.sipUsers.sipUsers" list: ${response.body}');
  }

  final items = list
      .whereType<Map<String, dynamic>>()
      .map(SipUser.fromJson)
      .toList();

  return SipUsersState(total: total, items: items);
});
