class ApiAuthResponse {
  const ApiAuthResponse({
    required this.accessToken,
    required this.tokenType,
    required this.expiresInMinutes,
    required this.geolocationRequired,
  });

  final String accessToken;
  final String tokenType;
  final int? expiresInMinutes;
  final bool geolocationRequired;

  factory ApiAuthResponse.fromJson(Map<String, dynamic> json) {
    return ApiAuthResponse(
      accessToken: json['access_token'] as String? ?? '',
      tokenType: json['token_type'] as String? ?? 'bearer',
      expiresInMinutes: (json['expires_in_minutes'] as num?)?.toInt(),
      geolocationRequired: json['geolocation_required'] as bool? ?? true,
    );
  }
}
