// services/transaction_api.dart
import 'dart:convert';
import 'package:asistenciapersonal1/models/last_transaction.dart';
import 'package:asistenciapersonal1/services/app_error.dart';
import 'package:asistenciapersonal1/services/api_client.dart';
import 'package:asistenciapersonal1/services/auth_service.dart';
import '../models/transaction_request.dart';

class TransactionApi {
  final String baseUrl;
  final ApiClient _client;

  TransactionApi({required this.baseUrl, ApiClient? client})
    : _client =
          client ??
          ApiClient(
            tokenProvider: AuthService.instance.getApiAccessToken,
            onUnauthorized: AuthService.instance.invalidateSession,
          );

  Future<void> sendTransaction(TransactionRequest tx) async {
    final url = Uri.parse('$baseUrl/api/logs/insert'); // 👈 ruta de FastAPI
    final bodyJson = jsonEncode(tx.toJson());

    final resp = await _client.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: bodyJson,
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw AppErrors.transactionFailed(resp.statusCode, resp.body);
    }
  }

  Future<LastTransaction> getLastTransaction(String empCode) async {
    final url = Uri.parse(
      '$baseUrl/api/logs/ultimo-registro/$empCode',
    ); // 👈 ruta de FastAPI

    final resp = await _client.get(url);

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw AppErrors.lastTransactionFailed(resp.statusCode, resp.body);
    }

    return lastTransactionFromJson(resp.body);
  }
}
