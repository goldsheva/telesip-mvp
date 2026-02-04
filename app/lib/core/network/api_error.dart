class ApiError {
  const ApiError({
    this.isSuccessful,
    this.code,
    this.errorMessage,
    this.errorMessageDetail,
  });

  final bool? isSuccessful;
  final int? code;
  final String? errorMessage;
  final String? errorMessageDetail;

  String get fallbackMessage =>
      errorMessageDetail ?? errorMessage ?? 'Unknown error';

  factory ApiError.fromJson(Map<String, dynamic> json) {
    return ApiError(
      isSuccessful: json['is_successful'] as bool?,
      code: (json['code'] as num?)?.toInt(),
      errorMessage: json['error_message'] as String?,
      errorMessageDetail: json['error_message_detail'] as String?,
    );
  }
}
