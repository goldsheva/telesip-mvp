import 'package:app/config/env_config.dart';
import 'package:app/core/network/api_exception.dart';
import 'package:app/core/network/graphql_client.dart';
import 'package:app/features/sip_users/models/sip_users_state.dart';

class SipUsersApi {
  const SipUsersApi(this._graphQLClient);

  final GraphqlClient _graphQLClient;

  Future<SipUsersState> fetchSipUsersState() async {
    const request = GraphqlRequest(
      query: _sipUsersQuery,
      operationName: 'sipUsers',
    );
    final decoded = await _graphQLClient.execute(request, EnvConfig.graphqlUrl);

    final errors = decoded['errors'];
    if (errors is List && errors.isNotEmpty) {
      final first = errors.first;
      final message = (first is Map && first['message'] is String)
          ? first['message'] as String
          : 'GraphQL error';
      throw ApiException.network(message);
    }

    final data = decoded['data'] as Map<String, dynamic>?;
    final sipUsersWrapper = data?['sipUsers'] as Map<String, dynamic>?;
    if (sipUsersWrapper == null) {
      throw ApiException.network('Missing sipUsers payload');
    }

    final total = (sipUsersWrapper['total'] as num?)?.toInt() ?? 0;
    final list = sipUsersWrapper['sipUsers'];
    if (list is! List) {
      throw ApiException.network('Unexpected sipUsers list');
    }

    final items = list
        .whereType<Map<String, dynamic>>()
        .map(SipUsersState.itemFromJson)
        .toList();

    return SipUsersState(total: total, items: items);
  }
}

const _sipUsersQuery = r'''
query sipUsers {
  sipUsers {
    total: total_count
    sipUsers: pbx_sip_users {
      sipUserId: pbx_sip_user_id
      userId: user_id
      sipLogin: sip_login
      sipPassword: sip_password
      dialplanId: dialplan_id
      dongleId: dongle_id
      pbxSipUrl: pbx_sip_url
      sipConnections: pbx_sip_connections {
        sipUrl: pbx_sip_url
        sipPort: pbx_sip_port
        sipProtocol: pbx_sip_protocol
      }
    }
    __typename
  }
}
''';
