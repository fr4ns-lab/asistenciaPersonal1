class DeviceRenewalAuthorizationResult {
  const DeviceRenewalAuthorizationResult({
    required this.empCode,
    required this.email,
    required this.authorizationId,
  });

  final String empCode;
  final String email;
  final String authorizationId;

  factory DeviceRenewalAuthorizationResult.fromJson(Map<String, dynamic> json) {
    return DeviceRenewalAuthorizationResult(
      empCode: _string(json['emp_code']),
      email: _string(json['email']),
      authorizationId: _string(json['authorization_id']),
    );
  }
}

class DeviceRenewalFailure {
  const DeviceRenewalFailure({required this.empCode, required this.detail});

  final String empCode;
  final String detail;

  factory DeviceRenewalFailure.fromJson(Map<String, dynamic> json) {
    return DeviceRenewalFailure(
      empCode: _string(json['emp_code']),
      detail: _string(json['detail']),
    );
  }
}

class DeviceRenewalActionResult {
  const DeviceRenewalActionResult({
    required this.authorized,
    required this.failed,
    required this.isRevocation,
  });

  final List<DeviceRenewalAuthorizationResult> authorized;
  final List<DeviceRenewalFailure> failed;
  final bool isRevocation;

  factory DeviceRenewalActionResult.fromJson(Map<String, dynamic> json) {
    final authorized = _list(json['authorized']);
    final isRevocation = authorized.isEmpty && json.containsKey('revoked');
    return DeviceRenewalActionResult(
      authorized:
          (authorized.isNotEmpty ? authorized : _list(json['revoked']))
              .map(DeviceRenewalAuthorizationResult.fromJson)
              .toList(),
      failed: _list(json['failed']).map(DeviceRenewalFailure.fromJson).toList(),
      isRevocation: isRevocation,
    );
  }
}

class DeviceReplacementStatus {
  const DeviceReplacementStatus({
    required this.allowed,
    required this.authorizationId,
    required this.expiresAt,
    required this.reason,
    required this.usedAt,
  });

  final bool allowed;
  final String authorizationId;
  final DateTime? expiresAt;
  final String reason;
  final DateTime? usedAt;

  factory DeviceReplacementStatus.fromJson(Map<String, dynamic> json) {
    return DeviceReplacementStatus(
      allowed: json['allowed'] as bool? ?? false,
      authorizationId: _string(json['authorizationId']),
      expiresAt: _date(json['expiresAt']),
      reason: _string(json['reason']),
      usedAt: _date(json['usedAt']),
    );
  }
}

class DeviceRenewalStatus {
  const DeviceRenewalStatus({
    required this.empCode,
    required this.email,
    required this.deviceReplacement,
  });

  final String empCode;
  final String email;
  final DeviceReplacementStatus? deviceReplacement;

  factory DeviceRenewalStatus.fromJson(Map<String, dynamic> json) {
    final replacement = _map(json['device_replacement']);
    return DeviceRenewalStatus(
      empCode: _string(json['emp_code']),
      email: _string(json['email']),
      deviceReplacement:
          replacement.isEmpty
              ? null
              : DeviceReplacementStatus.fromJson(replacement),
    );
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

List<Map<String, dynamic>> _list(Object? value) {
  if (value is! List) return const [];
  return value.map(_map).where((item) => item.isNotEmpty).toList();
}

String _string(Object? value) => value?.toString().trim() ?? '';

DateTime? _date(Object? value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
