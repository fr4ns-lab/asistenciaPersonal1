import 'dart:convert';

import 'package:asistenciapersonal1/models/device_renewal.dart';
import 'package:asistenciapersonal1/services/api_client.dart';
import 'package:asistenciapersonal1/services/app_error.dart';
import 'package:asistenciapersonal1/services/auth_service.dart';

class DeviceRenewalApiService {
  DeviceRenewalApiService({required this.baseUrl, ApiClient? client})
    : _client =
          client ??
          ApiClient(
            tokenProvider: AuthService.instance.getApiAccessToken,
            onUnauthorized: AuthService.instance.invalidateSession,
          );

  final String baseUrl;
  final ApiClient _client;

  Future<DeviceRenewalActionResult> authorize({
    required List<String> empCodes,
    required DateTime expiresAt,
    String? reason,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/admin/device-renewals/authorize'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'emp_codes': empCodes,
        'expires_at': _limaIso8601(expiresAt),
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      }),
    );

    final body = _responseMap(response.body, response.statusCode);
    return DeviceRenewalActionResult.fromJson(body);
  }

  Future<DeviceRenewalStatus> getStatus(String empCode) async {
    final url = Uri.parse(
      '$baseUrl/api/admin/device-renewals',
    ).replace(queryParameters: {'emp_code': empCode});
    final response = await _client.get(
      url,
      headers: const {'Content-Type': 'application/json'},
    );
    return DeviceRenewalStatus.fromJson(
      _responseMap(response.body, response.statusCode),
    );
  }

  Future<DeviceRenewalActionResult> revoke({
    required List<String> empCodes,
    String? reason,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/admin/device-renewals/revoke'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'emp_codes': empCodes,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      }),
    );

    final body = _responseMap(response.body, response.statusCode);
    return DeviceRenewalActionResult.fromJson(body);
  }

  Map<String, dynamic> _responseMap(String body, int statusCode) {
    if (statusCode < 200 || statusCode >= 300) {
      throw AppErrors.deviceRenewalFailed(statusCode, body);
    }

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      // The controlled error below is more useful to the administrator.
    }

    throw const AppException(
      code: 'ADMIN-DEVICE-RESP',
      message:
          'El servidor devolvió una respuesta inválida al administrar dispositivos.',
    );
  }

  String _limaIso8601(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}-'
        '${twoDigits(value.month)}-${twoDigits(value.day)}T'
        '${twoDigits(value.hour)}:${twoDigits(value.minute)}:'
        '${twoDigits(value.second)}-05:00';
  }
}
