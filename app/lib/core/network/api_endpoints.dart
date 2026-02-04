import 'package:app/config/env_config.dart';

class ApiEndpoints {
  static String get _baseApiUrl => EnvConfig.baseApiUrl;

  static String get authLogin => '$_baseApiUrl/auth/login';
  static String get authRefresh => '$_baseApiUrl/auth/refresh';

  static String get sipUsersList => '$_baseApiUrl/sip/users';
}
