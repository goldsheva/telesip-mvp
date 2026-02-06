import 'package:app/config/env_config.dart';

class ApiEndpoints {
  static String get _baseApiUrl => EnvConfig.baseApiUrl;

  static String get authLogin => '$_baseApiUrl/auth/login';

  static String get dongleList => '$_baseApiUrl/dongle';
  static String get sipUsersList => '$_baseApiUrl/sip-user';
}
