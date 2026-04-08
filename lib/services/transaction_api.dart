// services/transaction_api.dart
import 'dart:convert';
import 'package:asistenciapersonal1/models/last_transaction.dart';
import 'package:http/http.dart' as http;
import '../models/transaction_request.dart';

class TransactionApi {
  final String baseUrl;

  TransactionApi({required this.baseUrl});

  Future<void> sendTransaction(TransactionRequest tx) async {
    final url = Uri.parse('$baseUrl/api/logs/insert'); // 👈 ruta de FastAPI
    final bodyJson = jsonEncode(tx.toJson());

    final resp = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: bodyJson,
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Error API ${resp.statusCode}: ${resp.body}');
    }
  }

  Future<LastTransaction> getLastTransaction(String empCode) async {
    final url = Uri.parse(
      '$baseUrl/api/logs/ultimo-registro/$empCode',
    ); // 👈 ruta de FastAPI

    final resp = await http.get(url);

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Error API ${resp.statusCode}: ${resp.body}');
    }

    return lastTransactionFromJson(resp.body);
  }
}
