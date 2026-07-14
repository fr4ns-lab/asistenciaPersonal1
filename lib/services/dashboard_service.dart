import 'dart:convert';

import 'package:asistenciapersonal1/models/dashboard_response.dart';
import 'package:asistenciapersonal1/services/api_client.dart';
import 'package:asistenciapersonal1/services/app_error.dart';
import 'package:asistenciapersonal1/services/auth_service.dart';

class DashboardApiService {
  DashboardApiService({required this.baseUrl, ApiClient? client})
    : _client =
          client ??
          ApiClient(
            tokenProvider: AuthService.instance.getApiAccessToken,
            onUnauthorized: AuthService.instance.invalidateSession,
          );

  final String baseUrl;
  final ApiClient _client;

  Future<DashboardResponse> getMyDashboard({required DateTime month}) async {
    final normalizedMonth = DateTime(month.year, month.month);
    final monthValue =
        '${normalizedMonth.year}-${normalizedMonth.month.toString().padLeft(2, '0')}';
    final url = Uri.parse(
      '$baseUrl/api/dashboard/me',
    ).replace(queryParameters: {'month': monthValue});

    try {
      final response = await _client.get(
        url,
        headers: const {'Content-Type': 'application/json'},
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AppErrors.dashboardFailed(response.statusCode, response.body);
      }

      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) {
        throw const AppException(
          code: 'DASH-RESP',
          message:
              'No pudimos cargar tu panel de asistencia. Inténtalo nuevamente.',
          technicalDetail: 'La respuesta del panel no es un objeto JSON.',
        );
      }
      return DashboardResponse.fromJson(data);
    } on FirebaseSessionException {
      await AuthService.instance.invalidateSession();
      rethrow;
    } on ApiAuthenticationException {
      await AuthService.instance.invalidateSession();
      rethrow;
    } on ApiUnauthorizedException catch (error) {
      throw error.error;
    } on ApiOfflineException {
      throw AppErrors.apiUnavailable();
    }
  }
}

typedef DashboardService = DashboardApiService;
