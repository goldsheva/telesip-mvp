import 'dart:convert';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/network/api_endpoints.dart';
import 'package:app/features/sip_users/models/sip_user.dart';
import 'package:app/features/sip_users/models/sip_users_state.dart';

class SipUsersApi {
  const SipUsersApi(this._apiClient);

  final ApiClient _apiClient;

  Future<SipUsersState> fetchSipUsersState() async {
    final response = await _apiClient.get(ApiEndpoints.sipUsersList);

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

    final list = wrap['sipUsers'];
    if (list is! List) {
      throw Exception('Missing "data.sipUsers.sipUsers" list: ${response.body}');
    }

    final items = list
        .whereType<Map<String, dynamic>>()
        .map(SipUser.fromJson)
        .toList();

    final total = (wrap['total'] as num?)?.toInt() ?? 0;

    return SipUsersState(total: total, items: items);
  }

  Future<List<SipUser>> fetchSipUsers() => fetchSipUsersState().then((state) => state.items);

  Future<int> fetchTotal() => fetchSipUsersState().then((state) => state.total);
}
