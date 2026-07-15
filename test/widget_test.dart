import 'package:asistenciapersonal1/models/dashboard_response.dart';
import 'package:asistenciapersonal1/services/api_client.dart';
import 'package:asistenciapersonal1/services/app_error.dart';
import 'package:asistenciapersonal1/services/dashboard_service.dart';
import 'package:asistenciapersonal1/services/dashboard_refresh_notifier.dart';
import 'package:asistenciapersonal1/utils/lima_time.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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
        'summary': {
          'expected_working_days': 7,
          'worked_days': 6,
          'on_time_days': 5,
          'late_days': 1,
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
            'status': 'puntual',
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
      expect(dashboard.summary.onTimePercentage, 71.43);
      expect(dashboard.summary.attendanceLevel.key, 'buena');
      expect(dashboard.comparison.deltas.compliancePercentage, 12.5);
      expect(dashboard.comparison.improved.lateDays, isTrue);
      expect(dashboard.statusCounts['puntual'], 5);
      expect(dashboard.daily.single.status, 'puntual');
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
