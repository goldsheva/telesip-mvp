import 'dart:convert';
import 'package:app/config/api_endpoints.dart';
import 'package:app/models/dongle.dart';
import 'package:app/services/api_client.dart';

class DonglesApi {
  const DonglesApi(this._apiClient);

  final ApiClient _apiClient;

  Future<List<Dongle>> fetchDongles() async {
    final response = await _apiClient.get(ApiEndpoints.donglesList);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Dongles failed: ${response.statusCode} ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected response: ${response.body}');
    }

    final data = decoded['data'];
    if (data is! List) {
      throw Exception('Missing "data" list in response: ${response.body}');
    }

    return data
        .whereType<Map<String, dynamic>>()
        .map(Dongle.fromJson)
        .toList();
  }
}
