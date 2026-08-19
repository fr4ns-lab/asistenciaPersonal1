import 'dart:convert';

class AppException implements Exception {
  const AppException({
    required this.code,
    required this.message,
    this.technicalDetail,
  });

  final String code;
  final String message;
  final String? technicalDetail;

  String get userMessage => '$message\nCódigo: $code';

  @override
  String toString() {
    final detail = technicalDetail;
    if (detail == null || detail.isEmpty) return '$code: $message';
    return '$code: $message ($detail)';
  }
}

class AppErrors {
  AppErrors._();

  static const unknown = AppException(
    code: 'APP-001',
    message: 'Ocurrió un problema inesperado. Inténtalo nuevamente.',
  );

  static AppException authForbidden(String responseBody) {
    final detail = _apiDetail(responseBody);
    final normalized = detail.toLowerCase();

    if (normalized.contains('emp_code')) {
      return AppException(
        code: 'AUTH-403-EMP',
        message:
            'Tu usuario aún no está habilitado para marcar asistencia. Comunícate con el administrador.',
        technicalDetail: detail,
      );
    }

    return AppException(
      code: 'AUTH-403',
      message:
          'Tu cuenta no tiene permiso para usar esta aplicación. Comunícate con el administrador.',
      technicalDetail: detail,
    );
  }

  static AppException missingEmpCode() {
    return const AppException(
      code: 'AUTH-403-DNI',
      message:
          'Tu usuario aún no está habilitado para marcar asistencia. Comunícate con el administrador.',
      technicalDetail: 'No existe DNI local para enviar como emp_code.',
    );
  }

  static AppException firebaseTokenRejected(String responseBody) {
    return AppException(
      code: 'AUTH-401-FB',
      message: 'No pudimos validar tu sesión. Inicia sesión nuevamente.',
      technicalDetail: _apiDetail(responseBody),
    );
  }

  static AppException apiAuthUnexpected(int statusCode, String responseBody) {
    return AppException(
      code: 'AUTH-$statusCode',
      message:
          'No pudimos iniciar tu sesión en el servidor de asistencia. Inténtalo nuevamente.',
      technicalDetail: _shortBody(responseBody),
    );
  }

  static AppException apiUnavailable({String? technicalDetail}) {
    return AppException(
      code: 'API-503',
      message:
          'No pudimos conectar con el servidor de asistencia. Inténtalo nuevamente en unos minutos. O diríjase a un marcador de asistencia físico si es urgente.',
      technicalDetail: technicalDetail,
    );
  }

  static AppException sessionExpired() {
    return const AppException(
      code: 'AUTH-401',
      message: 'Tu sesión venció. Inicia sesión nuevamente.',
    );
  }

  static AppException transactionFailed(int statusCode, String responseBody) {
    final detail = _apiDetail(responseBody);

    if (statusCode == 401) return sessionExpired();
    if (statusCode == 403) {
      return AppException(
        code: 'MARK-403',
        message:
            'Tu usuario no tiene permiso para registrar asistencia. Comunícate con el administrador.',
        technicalDetail: detail,
      );
    }
    if (_isServerUnavailableStatus(statusCode)) {
      return apiUnavailable(technicalDetail: detail);
    }

    return AppException(
      code: 'MARK-$statusCode',
      message: 'No pudimos registrar tu marcación. Inténtalo nuevamente.',
      technicalDetail: detail,
    );
  }

  static AppException lastTransactionFailed(
    int statusCode,
    String responseBody,
  ) {
    final detail = _apiDetail(responseBody);

    if (statusCode == 401) return sessionExpired();
    if (_isServerUnavailableStatus(statusCode)) {
      return apiUnavailable(technicalDetail: detail);
    }

    return AppException(
      code: 'LAST-$statusCode',
      message:
          'No pudimos consultar tu última marcación. Inténtalo nuevamente.',
      technicalDetail: detail,
    );
  }

  static AppException dashboardFailed(int statusCode, String responseBody) {
    final detail = _apiDetail(responseBody);

    if (statusCode == 401) return sessionExpired();
    if (statusCode == 403) {
      if (detail.toLowerCase().contains('emp_code') ||
          detail.toLowerCase().contains('dni')) {
        return AppException(
          code: 'DASH-403-DNI',
          message:
              'Tu usuario aún no tiene DNI asociado para consultar asistencia. Comunícate con el administrador.',
          technicalDetail: detail,
        );
      }
      return AppException(
        code: 'DASH-403',
        message:
            'Tu usuario no tiene permiso para ver el panel de asistencia. Comunícate con el administrador.',
        technicalDetail: detail,
      );
    }
    if (_isServerUnavailableStatus(statusCode)) {
      return apiUnavailable(technicalDetail: detail);
    }

    return AppException(
      code: 'DASH-$statusCode',
      message:
          'No pudimos cargar tu panel de asistencia. Inténtalo nuevamente.',
      technicalDetail: detail,
    );
  }

  static AppException deviceRenewalFailed(int statusCode, String responseBody) {
    final detail = _apiDetail(responseBody);
    if (statusCode == 401) return sessionExpired();
    if (statusCode == 403) {
      return AppException(
        code: 'ADMIN-DEVICE-403',
        message: 'No tienes permisos para administrar dispositivos.',
        technicalDetail: detail,
      );
    }
    if (_isServerUnavailableStatus(statusCode)) {
      return apiUnavailable(technicalDetail: detail);
    }
    return AppException(
      code: 'ADMIN-DEVICE-$statusCode',
      message: 'No se pudo actualizar la autorización de dispositivo.',
      technicalDetail: detail,
    );
  }

  static bool _isServerUnavailableStatus(int statusCode) {
    return statusCode == 502 ||
        statusCode == 503 ||
        statusCode == 504 ||
        statusCode == 521 ||
        statusCode == 522 ||
        statusCode == 523 ||
        statusCode == 524 ||
        statusCode == 530;
  }

  static String _apiDetail(String responseBody) {
    try {
      final data = jsonDecode(responseBody);
      if (data is Map<String, dynamic>) {
        final detail = data['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          return detail.trim();
        }
      }
    } catch (_) {}

    return _shortBody(responseBody);
  }

  static String _shortBody(String responseBody) {
    final normalized = responseBody.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return 'Respuesta vacía';
    if (normalized.length <= 240) return normalized;
    return '${normalized.substring(0, 240)}...';
  }
}
