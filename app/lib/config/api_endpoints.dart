import 'env_config.dart';

class ApiEndpoints {
  static String get _baseApiUrl => EnvConfig.baseApiUrl;

  static String get authLogin => '$_baseApiUrl/auth/login';
  static String get authRefresh => '$_baseApiUrl/auth/refresh';

  static String get donglesList => '$_baseApiUrl/dongles';
}
