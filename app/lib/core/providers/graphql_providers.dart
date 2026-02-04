import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:app/core/network/graphql_client.dart';
import 'package:app/core/providers/network_providers.dart';

final graphqlClientProvider = Provider<GraphqlClient>((ref) {
  final apiClient = ref.read(apiClientProvider);
  return GraphqlClient(apiClient);
});
