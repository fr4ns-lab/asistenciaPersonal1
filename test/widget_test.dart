import 'dart:convert';

import 'package:asistenciapersonal1/models/admin_directory_user.dart';
import 'package:asistenciapersonal1/models/dashboard_response.dart';
import 'package:asistenciapersonal1/models/api_auth_response.dart';
import 'package:asistenciapersonal1/models/device_renewal.dart';
import 'package:asistenciapersonal1/pages/device_renewal_admin_page.dart';
import 'package:asistenciapersonal1/services/api_client.dart';
import 'package:asistenciapersonal1/services/app_error.dart';
import 'package:asistenciapersonal1/services/dashboard_service.dart';
import 'package:asistenciapersonal1/services/dashboard_refresh_notifier.dart';
import 'package:asistenciapersonal1/services/device_renewal_service.dart';
import 'package:asistenciapersonal1/utils/lima_time.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('ApiAuthResponse', () {
    test('exige geolocalización si el API no envía la política', () {
      final response = ApiAuthResponse.fromJson({'access_token': 'jwt'});

      expect(response.geolocationRequired, isTrue);
      expect(response.deviceValidationRequired, isTrue);
      expect(response.manageDeviceAuthorizations, isFalse);
    });

    test('respeta la política de geolocalización entregada por el API', () {
      final response = ApiAuthResponse.fromJson({
        'access_token': 'jwt',
        'geolocation_required': false,
      });

      expect(response.geolocationRequired, isFalse);
    });

    test('respeta la política de validación de dispositivo del API', () {
      final response = ApiAuthResponse.fromJson({
        'access_token': 'jwt',
        'device_validation_required': false,
      });

      expect(response.deviceValidationRequired, isFalse);
    });

    test('lee el permiso administrativo entregado por el API', () {
      final response = ApiAuthResponse.fromJson({
        'access_token': 'jwt',
        'permissions': {'manage_device_authorizations': true},
      });

      expect(response.manageDeviceAuthorizations, isTrue);
    });
  });

  group('AdministraciÃ³n de dispositivos', () {
    test('usa dni_by_email sin incluir datos del dispositivo', () {
      final user = AdminDirectoryUser.fromFirestore(
        documentId: 'jgallegos@lasalle.edu.pe',
        data: {
          'dni': '70551254',
          'name': 'Jhonny Gallegos',
          'deviceId': 'no-debe-usarse',
        },
      );

      expect(user.email, 'jgallegos@lasalle.edu.pe');
      expect(user.dni, '70551254');
      expect(user.displayName, 'Jhonny Gallegos');

      final userWithSpanishName = AdminDirectoryUser.fromFirestore(
        documentId: 'usuario@lasalle.edu.pe',
        data: {'dni': '12345678', 'nombre': 'Usuario de prueba'},
      );
      expect(userWithSpanishName.displayName, 'Usuario de prueba');
    });

    test('normaliza y elimina DNIs repetidos antes de enviarlos', () {
      final codes = parseEmpCodes('70551254, 12345678 70551254;\n87654321');

      expect(codes, ['70551254', '12345678', '87654321']);
    });

    test('autoriza renovaciones con JWT interno y vencimiento Lima', () async {
      final client = ApiClient(
        tokenProvider: ({required forceRefresh, rejectedToken}) async {
          expect(forceRefresh, isFalse);
          return 'jwt-interno';
        },
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/admin/device-renewals/authorize');
          expect(request.headers['Authorization'], 'Bearer jwt-interno');
          expect(request.headers['Content-Type'], 'application/json');

          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['emp_codes'], ['70551254', '12345678']);
          expect(body['expires_at'], '2026-08-31T23:59:59-05:00');
          expect(body['reason'], 'Cambio de equipo');

          return http.Response('''{
            "authorized": [
              {
                "emp_code": "70551254",
                "email": "usuario@lasalle.edu.pe",
                "authorization_id": "authorization-1"
              }
            ],
            "failed": [
              {"emp_code": "12345678", "detail": "Usuario no encontrado"}
            ]
          }''', 200);
        }),
      );
      final service = DeviceRenewalApiService(
        baseUrl: 'https://api.test',
        client: client,
      );

      final result = await service.authorize(
        empCodes: ['70551254', '12345678'],
        expiresAt: DateTime(2026, 8, 31, 23, 59, 59),
        reason: ' Cambio de equipo ',
      );

      expect(result.authorized.single.empCode, '70551254');
      expect(result.failed.single.detail, 'Usuario no encontrado');
      expect(result.isRevocation, isFalse);
      client.close();
    });

    test('identifica un resultado de revocación por DNI', () {
      final result = DeviceRenewalActionResult.fromJson({
        'revoked': [
          {'emp_code': '70551254', 'email': 'usuario@lasalle.edu.pe'},
        ],
        'failed': [],
      });

      expect(result.isRevocation, isTrue);
      expect(result.authorized.single.empCode, '70551254');
    });

    test('mapea 403 administrativo a un mensaje controlado', () async {
      final client = ApiClient(
        tokenProvider: ({required forceRefresh, rejectedToken}) async => 'jwt',
        httpClient: MockClient(
          (_) async => http.Response('{"detail":"forbidden"}', 403),
        ),
      );
      final service = DeviceRenewalApiService(
        baseUrl: 'https://api.test',
        client: client,
      );

      await expectLater(
        service.getStatus('70551254'),
        throwsA(
          isA<AppException>().having(
            (error) => error.code,
            'code',
            'ADMIN-DEVICE-403',
          ),
        ),
      );
      client.close();
    });

    test('interpreta el estado de renovaciÃ³n sin datos de dispositivo', () {
      final status = DeviceRenewalStatus.fromJson({
        'emp_code': '70551254',
        'email': 'usuario@lasalle.edu.pe',
        'device_replacement': {
          'allowed': true,
          'authorizationId': 'authorization-1',
          'expiresAt': '2026-08-31T23:59:59-05:00',
          'reason': 'Cambio de equipo',
          'usedAt': null,
        },
      });

      expect(status.deviceReplacement?.allowed, isTrue);
      expect(status.deviceReplacement?.authorizationId, 'authorization-1');
      expect(status.deviceReplacement?.expiresAt, isNotNull);
    });
  });

  group('ApiClient', () {
    test('agrega el token interno en el encabezado Authorization', () async {
      final client = ApiClient(
        tokenProvider: ({required forceRefresh, rejectedToken}) async {
          expect(forceRefresh, isFalse);
          expect(rejectedToken, isNull);
          return 'jwt-interno';
        },
        httpClient: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer jwt-interno');
          return http.Response('ok', 200);
        }),
      );

      final response = await client.get(
        Uri.parse('https://api.test/protected'),
      );

      expect(response.statusCode, 200);
      client.close();
    });

    test('renueva el token y reintenta una sola vez ante HTTP 401', () async {
      final usedTokens = <String>[];
      var tokenCalls = 0;

      final client = ApiClient(
        tokenProvider: ({required forceRefresh, rejectedToken}) async {
          tokenCalls++;
          if (!forceRefresh) {
            expect(rejectedToken, isNull);
            return 'jwt-vencido';
          }

          expect(rejectedToken, 'jwt-vencido');
          return 'jwt-renovado';
        },
        httpClient: MockClient((request) async {
          usedTokens.add(request.headers['Authorization'] ?? '');
          expect(request.body, '{"tipo":"entrada"}');

          if (usedTokens.length == 1) {
            return http.Response('unauthorized', 401);
          }

          return http.Response('ok', 200);
        }),
      );

      final response = await client.post(
        Uri.parse('https://api.test/logs/insert'),
        body: '{"tipo":"entrada"}',
      );

      expect(response.statusCode, 200);
      expect(tokenCalls, 2);
      expect(usedTokens, ['Bearer jwt-vencido', 'Bearer jwt-renovado']);
      client.close();
    });

    test(
      'notifica sesión inválida si el reintento también devuelve 401',
      () async {
        var unauthorizedCalls = 0;

        final client = ApiClient(
          tokenProvider: ({required forceRefresh, rejectedToken}) async {
            return forceRefresh ? 'jwt-renovado' : 'jwt-vencido';
          },
          onUnauthorized: () async {
            unauthorizedCalls++;
          },
          httpClient: MockClient((request) async {
            return http.Response('unauthorized', 401);
          }),
        );

        final response = await client.get(
          Uri.parse('https://api.test/protected'),
        );

        expect(response.statusCode, 401);
        expect(unauthorizedCalls, 1);
        client.close();
      },
    );
  });

  group('AppErrors', () {
    test('mapea falta de emp_code a mensaje de soporte controlado', () {
      final error = AppErrors.authForbidden(
        '{"detail":"usuario no tiene emp_code asociado"}',
      );

      expect(error.code, 'AUTH-403-EMP');
      expect(error.userMessage, contains('Código: AUTH-403-EMP'));
      expect(error.userMessage, isNot(contains('emp_code')));
      expect(error.technicalDetail, contains('emp_code'));
    });

    test('mapea fallo de marcación 401 a sesión vencida', () {
      final error = AppErrors.transactionFailed(401, '{"detail":"expired"}');

      expect(error.code, 'AUTH-401');
      expect(error.userMessage, contains('Tu sesión venció'));
    });
  });

  group('DashboardResponse', () {
    test('parsea el contrato de /api/dashboard/me', () {
      final dashboard = DashboardResponse.fromJson({
        'employee': {
          'emp_code': '70551254',
          'name': 'Jhonny GALLEGOS',
          'email': 'jgallegos@lasalle.edu.pe',
        },
        'period': {'from': '2026-07-01', 'to': '2026-07-31'},
        'evaluation_period': {
          'from': '2026-07-01',
          'to': '2026-07-15',
          'is_complete': false,
        },
        'summary': {
          'expected_working_days': 7,
          'worked_days': 6,
          'complete_mark_days': 5,
          'incomplete_mark_days': 1,
          'month_expected_working_days': 23,
          'remaining_scheduled_days': 13,
          'evaluated_through': '2026-07-15',
          'on_time_days': 5,
          'late_days': 1,
          'late_minutes_total': 4,
          'late_minutes_label': '4 minutos de tardanza acumulada',
          'early_departure_days': 1,
          'early_departure_minutes_total': 10,
          'early_departure_minutes_label':
              '10 minutos de salida anticipada acumulada',
          'schedule_incidence_minutes_total': 14,
          'schedule_incidence_minutes_label':
              '14 minutos de incidencias de horario',
          'missing_days': 1,
          'free_days': 2,
          'on_time_percentage': 71.43,
          'compliance_percentage': 85.71,
          'attendance_level': {'key': 'buena', 'label': 'Asistencia buena'},
          'worked_days_label': '6 días con marca de 7 días programados',
          'missing_days_label': '1 día programado sin marca',
        },
        'comparison': {
          'previous_period': {
            'from': '2026-06-01',
            'to': '2026-06-30',
            'month': '2026-06',
          },
          'previous_summary': {},
          'deltas': {
            'worked_days': 1,
            'on_time_days': 2,
            'late_days': -1,
            'missing_days': -1,
            'on_time_percentage': 10.0,
            'compliance_percentage': 12.5,
          },
          'improved': {
            'late_days': true,
            'missing_days': true,
            'on_time_percentage': true,
            'compliance_percentage': true,
          },
        },
        'status_counts': {'puntual': 5, 'tarde': 1},
        'daily': [
          {
            'date': '2026-07-09',
            'schedule': 'Horario regular',
            'expected_in': '07:30',
            'expected_out': '15:30',
            'first_punch': '07:22',
            'last_punch': '12:25',
            'punch_count': 7,
            'mark_status': 'completa',
            'status': 'puntual',
            'late_minutes': 0,
            'late_arrival_minutes': 0,
            'early_departure_minutes': 0,
            'schedule_incidence_minutes': 0,
          },
        ],
        'recent_checkins': [
          {
            'id': 123,
            'punch_date': '2026-07-09',
            'punch_time': '07:22',
            'punch_state': '0',
            'terminal_alias': 'APP',
            'gps_location': 'Lima',
            'latitude': -12.0,
            'longitude': -77.0,
          },
        ],
      });

      expect(dashboard.employee.empCode, '70551254');
      expect(dashboard.employee.email, 'jgallegos@lasalle.edu.pe');
      expect(dashboard.evaluationPeriod.isComplete, isFalse);
      expect(dashboard.evaluationPeriod.to, '2026-07-15');
      expect(dashboard.summary.onTimePercentage, 71.43);
      expect(dashboard.summary.monthExpectedWorkingDays, 23);
      expect(dashboard.summary.remainingScheduledDays, 13);
      expect(dashboard.summary.lateMinutesTotal, 4);
      expect(dashboard.summary.incompleteMarkDays, 1);
      expect(dashboard.summary.earlyDepartureMinutesTotal, 10);
      expect(dashboard.summary.scheduleIncidenceMinutesTotal, 14);
      expect(dashboard.summary.attendanceLevel.key, 'buena');
      expect(dashboard.comparison.deltas.compliancePercentage, 12.5);
      expect(dashboard.comparison.improved.lateDays, isTrue);
      expect(dashboard.statusCounts['puntual'], 5);
      expect(dashboard.daily.single.status, 'puntual');
      expect(dashboard.daily.single.markStatus, 'completa');
      expect(dashboard.daily.single.lateMinutes, 0);
      expect(dashboard.recentCheckins.single.terminalAlias, 'APP');
      expect(dashboard.hasData, isTrue);
    });
  });

  group('DashboardApiService', () {
    test('consulta el periodo solicitado con el JWT interno', () async {
      final client = ApiClient(
        tokenProvider: ({required forceRefresh, rejectedToken}) async {
          return 'jwt-interno';
        },
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/dashboard/me');
          expect(request.url.queryParameters['month'], '2026-07');
          expect(request.headers['Authorization'], 'Bearer jwt-interno');
          return http.Response('''{
              "employee": {},
              "period": {},
              "summary": {},
              "comparison": {},
              "status_counts": {},
              "daily": [],
              "recent_checkins": []
            }''', 200);
        }),
      );
      final service = DashboardApiService(
        baseUrl: 'https://api.test',
        client: client,
      );

      final dashboard = await service.getMyDashboard(
        month: DateTime(2026, 7, 14),
      );

      expect(dashboard.hasData, isFalse);
      client.close();
    });
  });

  group('LimaTime', () {
    test('convierte un timestamp UTC del API a hora Lima', () {
      final date = LimaTime.parseApiTimestamp('2026-07-15T12:31:00Z');

      expect(date.hour, 7);
      expect(date.minute, 31);
    });

    test('trata timestamps API sin zona explícita como UTC', () {
      final date = LimaTime.parseApiTimestamp('2026-07-15T12:31:00');

      expect(date.hour, 7);
      expect(date.minute, 31);
    });
  });

  test('notifica al dashboard después de una marcación confirmada', () {
    var notifications = 0;
    void listener() => notifications++;

    DashboardRefreshNotifier.instance.addListener(listener);
    DashboardRefreshNotifier.instance.notifyCheckInRegistered();
    DashboardRefreshNotifier.instance.removeListener(listener);

    expect(notifications, 1);
  });
}
