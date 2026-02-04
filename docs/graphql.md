### GraphQL endpoint

- URL: `https://teleleo.k8s-stage.bringo.tel/api/` (or `https://teleleo.com/api/` for `prod`)
- Authentication: same `Authorization: Bearer <JWT>` header as REST.

### `sipUsers` query

```graphql
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
```

#### Fragments used

`SipUser_` expands `SipUserNoNesting` and optionally includes `Dongle` when `$withDongle` is `true`.  
`SipUserNoNesting` already aliases the server fields to the DTO names (`sipUserId`, `sipLogin`, `pbxSipUrl`, etc.).  
`SipConnectionNoNesting` maps `pbx_sip_connection` fields to the DTO used in `SipConnection`.

#### Variables

```json
{
  "withDongle": false,
  "isShort": false
}
```

`withDongle` controls whether the nested dongle metadata is returned, and `isShort` decides whether the fragment `DongleNoNesting` is expanded or skipped.

Errors are returned via the standard GraphQL `errors` array; the client surfaces the first message through `ApiException.network()`.
