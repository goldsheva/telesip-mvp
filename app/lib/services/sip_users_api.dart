import 'dart:convert';
import 'package:app/config/api_endpoints.dart';
import 'package:app/models/sip_user.dart';
import 'package:app/services/api_client.dart';

class SipUsersApi {
  const SipUsersApi(this._apiClient);

  final ApiClient _apiClient;

  Future<List<SipUser>> fetchSipUsers() async {
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

    final sipUsersWrap = data['sipUsers'];
    if (sipUsersWrap is! Map<String, dynamic>) {
      throw Exception('Missing "data.sipUsers" object: ${response.body}');
    }

    final list = sipUsersWrap['sipUsers'];
    if (list is! List) {
      throw Exception('Missing "data.sipUsers.sipUsers" list: ${response.body}');
    }

    return list
        .whereType<Map<String, dynamic>>()
        .map(SipUser.fromJson)
        .toList();
  }

  Future<int> fetchTotal() async {
    final response = await _apiClient.get(ApiEndpoints.sipUsersList);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('SipUsers failed: ${response.statusCode} ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    final data = (decoded is Map<String, dynamic>) ? decoded['data'] : null;
    final wrap = (data is Map<String, dynamic>) ? data['sipUsers'] : null;
    final total = (wrap is Map<String, dynamic>) ? wrap['total'] : null;

    return (total as num?)?.toInt() ?? 0;
  }
}
