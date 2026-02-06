import 'dart:convert';

import 'package:app/features/sip_users/models/pbx_sip_user.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class GeneralSipCredentials {
  const GeneralSipCredentials({
    required this.sipUserId,
    required this.sipLogin,
    required this.sipPassword,
  });

  final int sipUserId;
  final String sipLogin;
  final String sipPassword;

  Map<String, String> toJson() => <String, String>{
    'sip_user_id': sipUserId.toString(),
    'sip_login': sipLogin,
    'sip_password': sipPassword,
  };

  factory GeneralSipCredentials.fromJson(Map<String, dynamic> json) {
    final idValue = json['sip_user_id'];
    final sipUserId = idValue is int
        ? idValue
        : int.parse(idValue?.toString() ?? '0');

    return GeneralSipCredentials(
      sipUserId: sipUserId,
      sipLogin: json['sip_login'] as String,
      sipPassword: json['sip_password'] as String,
    );
  }

  factory GeneralSipCredentials.fromSipUser(PbxSipUser sipUser) {
    return GeneralSipCredentials(
      sipUserId: sipUser.sipUserId,
      sipLogin: sipUser.sipLogin,
      sipPassword: sipUser.sipPassword,
    );
  }
}

class GeneralSipCredentialsStorage {
  const GeneralSipCredentialsStorage(this._storage);

  final FlutterSecureStorage _storage;

  static const _key = 'general_sip_credentials';

  Future<GeneralSipCredentials?> readCredentials() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;

    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    return GeneralSipCredentials.fromJson(decoded);
  }

  Future<void> writeCredentials(GeneralSipCredentials credentials) async {
    await _storage.write(key: _key, value: jsonEncode(credentials.toJson()));
  }

  Future<void> clear() async {
    await _storage.delete(key: _key);
  }
}
