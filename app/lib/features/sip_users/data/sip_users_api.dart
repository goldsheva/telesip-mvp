import 'dart:convert';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/network/api_endpoints.dart';
import 'package:app/core/network/api_exception.dart';
import 'package:app/features/sip_users/models/sip_users_state.dart';

class SipUsersApi {
  const SipUsersApi(this._apiClient);

  final ApiClient _apiClient;

  Future<SipUsersState> fetchSipUsersState() async {
    final response = await _apiClient.get(ApiEndpoints.sipUsersList);

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException.network('Unexpected sip users payload');
    }

    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw ApiException.network('Missing sip users data');
    }

    final total = (data['total_count'] as num?)?.toInt() ?? 0;
    final list = data['pbx_sip_users'];
    if (list is! List) {
      throw ApiException.network('Unexpected sip users list');
    }

    final items = list
        .whereType<Map<String, dynamic>>()
        .map(SipUsersState.itemFromJson)
        .toList();

    return SipUsersState(total: total, items: items);
  }
}
