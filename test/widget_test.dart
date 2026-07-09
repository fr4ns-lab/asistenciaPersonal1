import 'package:asistenciapersonal1/services/api_client.dart';
import 'package:asistenciapersonal1/services/app_error.dart';
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
}
