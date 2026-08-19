class ApiAuthResponse {
  const ApiAuthResponse({
    required this.accessToken,
    required this.tokenType,
    required this.expiresInMinutes,
    required this.geolocationRequired,
    required this.deviceValidationRequired,
    required this.manageDeviceAuthorizations,
  });

  final String accessToken;
  final String tokenType;
  final int? expiresInMinutes;
  final bool geolocationRequired;
  final bool deviceValidationRequired;
  final bool manageDeviceAuthorizations;

  factory ApiAuthResponse.fromJson(Map<String, dynamic> json) {
    final permissions = json['permissions'];
    final permissionsMap =
        permissions is Map ? Map<String, dynamic>.from(permissions) : const {};

    return ApiAuthResponse(
      accessToken: json['access_token'] as String? ?? '',
      tokenType: json['token_type'] as String? ?? 'bearer',
      expiresInMinutes: (json['expires_in_minutes'] as num?)?.toInt(),
      geolocationRequired: json['geolocation_required'] as bool? ?? true,
      deviceValidationRequired:
          json['device_validation_required'] as bool? ?? true,
      manageDeviceAuthorizations:
          permissionsMap['manage_device_authorizations'] as bool? ?? false,
    );
  }
}
