import 'dart:convert';

import 'package:app/config/env_config.dart';
import 'package:app/core/network/api_client.dart';
import 'package:app/core/network/api_endpoints.dart';
import 'package:app/features/dongles/models/dongle.dart';

class DonglesApi {
  const DonglesApi(this._apiClient);

  final ApiClient _apiClient;

  Future<List<Dongle>> fetchDongles() async {
    final uri = Uri.parse(ApiEndpoints.donglesList).replace(
      queryParameters: {'site_domain_id': EnvConfig.siteDomainId.toString()},
    );
    final response = await _apiClient.get(uri.toString());

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Dongles failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected response: ${response.body}');
    }

    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('Missing "data" object in response: ${response.body}');
    }

    final list = data['dongles'];
    if (list is! List) {
      throw Exception(
        'Missing "data.dongles" list in response: ${response.body}',
      );
    }

    return list.whereType<Map<String, dynamic>>().map(Dongle.fromJson).toList();
  }
}
