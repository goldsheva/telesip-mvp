import 'package:app/core/network/api_client.dart';
import 'package:app/core/network/api_endpoints.dart';

class FcmTokenApi {
  const FcmTokenApi(this._apiClient);

  final ApiClient _apiClient;

  Future<void> registerToken({required String token}) async {
    await _apiClient.post(ApiEndpoints.sipUserToken, {'token': token});
  }
}
