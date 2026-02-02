import 'env_config.dart';

class ApiEndpoints {
  static String get _baseApiUrl => EnvConfig.baseApiUrl;

  static String get authLogin => '$_baseApiUrl/auth/login';
}
