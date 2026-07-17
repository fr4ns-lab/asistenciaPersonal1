import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

typedef ApiTokenProvider =
    Future<String> Function({
      required bool forceRefresh,
      String? rejectedToken,
    });
typedef UnauthorizedHandler = Future<void> Function();

class ApiClient {
  ApiClient({
    required ApiTokenProvider tokenProvider,
    UnauthorizedHandler? onUnauthorized,
    http.Client? httpClient,
  }) : _tokenProvider = tokenProvider,
       _onUnauthorized = onUnauthorized,
       _httpClient = httpClient ?? http.Client();

  final ApiTokenProvider _tokenProvider;
  final UnauthorizedHandler? _onUnauthorized;
  final http.Client _httpClient;

  Future<http.Response> get(Uri url, {Map<String, String>? headers}) {
    return _send(method: 'GET', url: url, headers: headers);
  }

  Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return _send(method: 'POST', url: url, headers: headers, body: body);
  }

  Future<http.Response> _send({
    required String method,
    required Uri url,
    Map<String, String>? headers,
    Object? body,
  }) async {
    final bodyBytes = _encodeBody(body);
    final firstToken = await _tokenProvider(
      forceRefresh: false,
      rejectedToken: null,
    );
    var response = await _sendOnce(
      method: method,
      url: url,
      headers: headers,
      bodyBytes: bodyBytes,
      token: firstToken,
    );

    if (response.statusCode != 401) return response;

    final renewedToken = await _tokenProvider(
      forceRefresh: true,
      rejectedToken: firstToken,
    );
    response = await _sendOnce(
      method: method,
      url: url,
      headers: headers,
      bodyBytes: bodyBytes,
      token: renewedToken,
    );
    if (response.statusCode == 401) {
      await _onUnauthorized?.call();
    }
    return response;
  }

  Future<http.Response> _sendOnce({
    required String method,
    required Uri url,
    required Uint8List? bodyBytes,
    required String token,
    Map<String, String>? headers,
  }) async {
    final request = http.Request(method, url);
    request.headers.addAll({...?headers, 'Authorization': 'Bearer $token'});
    if (bodyBytes != null) request.bodyBytes = bodyBytes;

    final streamedResponse = await _httpClient.send(request);
    return http.Response.fromStream(streamedResponse);
  }

  Uint8List? _encodeBody(Object? body) {
    if (body == null) return null;
    if (body is Uint8List) return body;
    if (body is List<int>) return Uint8List.fromList(body);
    return Uint8List.fromList(utf8.encode(body.toString()));
  }

  void close() => _httpClient.close();
}
