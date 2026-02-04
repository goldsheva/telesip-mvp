import 'dart:convert';

import 'package:app/core/network/api_client.dart';
import 'package:app/core/network/api_exception.dart';

class GraphqlRequest {
  const GraphqlRequest({
    required this.query,
    this.operationName,
    this.variables,
  });

  final String query;
  final String? operationName;
  final Map<String, dynamic>? variables;

  Map<String, dynamic> toJson() {
    final payload = <String, dynamic>{'query': query};
    if (operationName != null) {
      payload['operationName'] = operationName;
    }
    if (variables != null && variables!.isNotEmpty) {
      payload['variables'] = variables;
    }
    return payload;
  }
}

class GraphqlClient {
  const GraphqlClient(this._client);

  final ApiClient _client;

  Future<Map<String, dynamic>> execute(
    GraphqlRequest request,
    String endpoint,
  ) async {
    final response = await _client.post(endpoint, request.toJson());

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException.network('Unexpected GraphQL payload');
    }

    return decoded;
  }
}
