import 'dart:convert';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/network/api_endpoints.dart';
import 'package:app/core/network/api_exception.dart';
import 'package:app/features/dongles/models/dongle.dart';

class DonglesApi {
  const DonglesApi(this._client);

  final ApiClient _client;

  Future<List<Dongle>> fetchDongles() async {
    final response = await _client.get(ApiEndpoints.dongleList);

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException.network('Unexpected dongles payload');
    }

    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw ApiException.network('Missing dongles data');
    }

    final list = data['dongles'];
    if (list is! List) {
      throw ApiException.network('Unexpected dongles list');
    }

    return list.whereType<Map<String, dynamic>>().map(Dongle.fromJson).toList();
  }
}
