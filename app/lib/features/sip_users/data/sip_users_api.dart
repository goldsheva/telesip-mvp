import 'package:app/config/env_config.dart';
import 'package:app/core/network/api_exception.dart';
import 'package:app/core/network/graphql_client.dart';
import 'package:app/features/sip_users/models/sip_users_state.dart';

class SipUsersApi {
  const SipUsersApi(this._graphQLClient);

  final GraphqlClient _graphQLClient;

  static const _request = GraphqlRequest(
    query: _sipUsersQuery,
    operationName: 'sipUsers',
    variables: _sipUsersVariables,
  );

  Future<SipUsersState> fetchSipUsersState() async {
    final decoded = await _graphQLClient.execute(
      _request,
      EnvConfig.graphqlUrl,
    );

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

const _sipUsersVariables = {'withDongle': false, 'isShort': false};

const _sipUsersQuery = r'''
query sipUsers($withDongle: Boolean = false, $isShort: Boolean = false) {
  sipUsers {
    total: total_count
    sipUsers: pbx_sip_users {
      ...SipUser_
      __typename
    }
    __typename
  }
}

fragment SipUser_ on SipUser {
  ...SipUserNoNesting
  Dongle @include(if: $withDongle) {
    ...DongleNoNesting
    __typename
  }
  __typename
}

fragment SipUserNoNesting on SipUser {
  sipUserId: pbx_sip_user_id
  userId: user_id
  sipLogin: sip_login
  sipPassword: sip_password
  dialplanId: dialplan_id
  dongleId: dongle_id
  pbxSipUrl: pbx_sip_url
  sipConnections: pbx_sip_connections {
    ...SipConnectionNoNesting
    __typename
  }
  __typename
}

fragment SipConnectionNoNesting on SipConnection {
  sipUrl: pbx_sip_url
  sipPort: pbx_sip_port
  sipProtocol: pbx_sip_protocol
  __typename
}

fragment DongleNoNesting on Dongle {
  ...DongleShort
  ... on Dongle @skip(if: $isShort) {
    bootstrapDongleId: bootstrap_dongle_id
    userId: user_id
    hotspotName: hotspot_name
    hotspotPassword: hotspot_password
    imeiFake: imei_fake
    isDeleted: is_deleted
    apiVersion: api_version
    isHotspotEnable: is_hotspot_enable
    smsOutgoing: sms_outgoing
    smsIncoming: sms_incoming
    callOutgoing: call_outgoing
    callIncoming: call_incoming
    createdAt: created_at
    updatedAt: updated_at
    activatedAt: activated_at
    tariffPackageId: tariff_package_id
    tariffPackageEnd: tariff_package_end
    imsi
    iccid
    mcc
    dailySmsLimit: daily_sms_limit
    dongleSignalQualityId: dongle_signal_quality_id
    isSendReport: is_send_report
    isPublicVpnEnabled: is_public_vpn_enabled
    isMuteIncomingCall: is_mute_incoming_call
    publicVpnEndpoint: public_vpn_endpoint
    publicVpnLogin: public_vpn_login
    publicVpnPassword: public_vpn_password
    isVPNConnected: is_vpn_connected
    dialplanId: dialplan_id
    dongleFlags: dongle_flags {
      ...DongleFlag_
      __typename
    }
    __typename
  }
  __typename
}

fragment DongleShort on Dongle {
  dongleId: dongle_id
  name
  phoneNumber: number
  isTrial: is_trial
  trialEnd: trial_end
  isTariffPackageActive: is_tariff_package_active
  isTariffPackageEnabled: is_tariff_package_enabled
  isOnline: is_online
  dongleOnlineStatus: dongle_online_status
  dongleOnlineErrorCodeId: dongle_online_error_code_id
  dongleCallTypeId: dongle_call_type_id
  isActive: is_active
  displayStatus: display_status
  __typename
}

fragment DongleFlag_ on DongleFlag {
  dongleFlagId: dongle_flag_id
  name
  __typename
}
''';
