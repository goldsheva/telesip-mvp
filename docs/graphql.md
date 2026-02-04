### GraphQL endpoint

- URL: `https://teleleo.k8s-stage.bringo.tel/api/` (or `https://teleleo.com/api/` for `prod`)
- Authentication: same `Authorization: Bearer <JWT>` header as REST.

### `sipUsers` query

```graphql
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
  }
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
