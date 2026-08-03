import 'dart:convert';
import 'dart:io';

import 'package:asistenciapersonal1/models/api_auth_response.dart';
import 'package:asistenciapersonal1/services/app_error.dart';
import 'package:asistenciapersonal1/services/api_config.dart';
import 'package:asistenciapersonal1/services/token_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class AuthResult {
  final User user;
  final String? resolvedPhotoUrl;

  AuthResult({required this.user, required this.resolvedPhotoUrl});
}

enum ApiSessionStatus {
  authenticated,
  unauthenticated,
  offline,
  unauthorized,
  error,
}

class ApiSessionState {
  const ApiSessionState(
    this.status, {
    this.message,
    this.geolocationRequired = true,
    this.deviceValidationRequired = true,
  });

  final ApiSessionStatus status;
  final String? message;
  final bool geolocationRequired;
  final bool deviceValidationRequired;
}

class ApiOfflineException implements Exception {
  const ApiOfflineException();
}

class ApiUnauthorizedException implements Exception {
  const ApiUnauthorizedException(this.error);

  final AppException error;

  String get message => error.userMessage;

  @override
  String toString() => error.toString();
}

class FirebaseSessionException implements Exception {
  const FirebaseSessionException();
}

class ApiAuthenticationException implements Exception {
  const ApiAuthenticationException(this.error);

  final AppException error;

  String get message => error.userMessage;

  @override
  String toString() => error.toString();
}

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();
  static const _deviceIdKey = 'device_id';

  final _uuid = const Uuid();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TokenStorage _tokenStorage = TokenStorage();
  final http.Client _apiHttpClient = http.Client();

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _googleInitialized = false;
  Future<String>? _tokenRenewal;

  String _emailToDocId(String email) {
    return email.toLowerCase().trim().split('@').first;
  }

  void _showSnack(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    await _googleSignIn.initialize();
    _googleInitialized = true;
  }

  Future<String?> _getDniFromEmail(String? email) async {
    if (email == null || email.isEmpty) return null;

    final normalized = email.toLowerCase().trim();
    final doc = await _db.collection('dni_by_email').doc(normalized).get();

    if (!doc.exists) return null;
    final dni = doc.data()?['dni'];
    if (dni is! String || dni.trim().isEmpty) return null;
    return dni.trim();
  }

  Future<String> _getDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_deviceIdKey);

      if (saved != null && saved.isNotEmpty) {
        return saved;
      }

      final newId = _uuid.v4();
      await prefs.setString(_deviceIdKey, newId);
      return newId;
    } catch (_) {
      return 'temp_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  Future<String?> _fetchPhotoFromUserInfo(String accessToken) async {
    try {
      final res = await http.get(
        Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'X-Goog-AuthUser': '0',
        },
      );

      debugPrint('userinfo status: ${res.statusCode}');
      debugPrint('userinfo body: ${res.body}');

      if (res.statusCode != 200) return null;

      final data = json.decode(res.body) as Map<String, dynamic>;
      final picture = data['picture'] as String?;

      if (picture == null || picture.trim().isEmpty) return null;
      return picture.trim();
    } catch (e) {
      debugPrint('Error userinfo photo: $e');
      return null;
    }
  }

  Future<String?> _fetchPhotoFromPeopleApi(String accessToken) async {
    try {
      final res = await http.get(
        Uri.parse(
          'https://people.googleapis.com/v1/people/me?personFields=photos',
        ),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'X-Goog-AuthUser': '0',
        },
      );

      debugPrint('people/me status: ${res.statusCode}');
      debugPrint('people/me body: ${res.body}');

      if (res.statusCode != 200) return null;

      final data = json.decode(res.body) as Map<String, dynamic>;
      final photos = (data['photos'] as List?) ?? [];

      if (photos.isEmpty) return null;

      final first = photos.first;
      if (first is! Map<String, dynamic>) return null;

      final url = first['url'] as String?;
      if (url == null || url.trim().isEmpty) return null;

      return url.trim();
    } catch (e) {
      debugPrint('Error people api photo: $e');
      return null;
    }
  }

  Future<String?> _resolvePhotoUrl({
    required GoogleSignInAccount googleUser,
    required User firebaseUser,
  }) async {
    String? url;

    if (googleUser.photoUrl != null && googleUser.photoUrl!.trim().isNotEmpty) {
      url = googleUser.photoUrl!.trim();
    }

    if ((url == null || url.isEmpty) &&
        firebaseUser.photoURL != null &&
        firebaseUser.photoURL!.trim().isNotEmpty) {
      url = firebaseUser.photoURL!.trim();
    }

    return url;
  }

  Future<AuthResult?> signInWithGoogle(BuildContext context) async {
    try {
      await _ensureGoogleInitialized();
      await _tokenStorage.clearAccessToken();

      GoogleSignInAccount? googleUser;

      if (_googleSignIn.supportsAuthenticate()) {
        googleUser = await _googleSignIn.authenticate();
      }

      if (googleUser == null) return null;

      const allowedDomain = 'lasalle.edu.pe';
      final email = googleUser.email.trim().toLowerCase();

      if (!email.endsWith('@$allowedDomain')) {
        try {
          await _googleSignIn.disconnect();
        } catch (_) {}
        _showSnack(
          context,
          'Solo se permite el ingreso con correos institucionales.',
        );
        return null;
      }

      final googleAuth = googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      final firebaseUser = userCredential.user;

      if (firebaseUser == null) return null;

      final resolvedPhoto = await _resolvePhotoUrl(
        googleUser: googleUser,
        firebaseUser: firebaseUser,
      );

      final docId = _emailToDocId(email);

      await _db.collection('users').doc(docId).set({
        'email': email,
        'name': firebaseUser.displayName ?? googleUser.displayName,
        'photoUrl': resolvedPhoto,
        'firebaseUid': firebaseUser.uid,
        'lastLogin': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return AuthResult(user: firebaseUser, resolvedPhotoUrl: resolvedPhoto);
    } catch (e) {
      debugPrint('Error al iniciar sesión: $e');
      _showSnack(
        context,
        const AppException(
          code: 'AUTH-LOGIN',
          message: 'No pudimos iniciar sesión. Inténtalo nuevamente.',
        ).userMessage,
      );
      return null;
    }
  }

  Future<void> signOut(BuildContext context) async {
    try {
      await _clearAllSessions();
    } catch (e) {
      debugPrint('Error al cerrar sesión: $e');
      _showSnack(
        context,
        const AppException(
          code: 'AUTH-SIGNOUT',
          message: 'No pudimos cerrar sesión correctamente.',
        ).userMessage,
      );
    }
  }

  Future<void> invalidateSession() => _clearAllSessions();

  Future<ApiSessionState> restoreApiSession() async {
    if (_auth.currentUser == null) {
      await _tokenStorage.clearAccessToken();
      return const ApiSessionState(ApiSessionStatus.unauthenticated);
    }

    try {
      await getApiAccessToken(forceRefresh: false);
      final geolocationRequired = await _tokenStorage.readGeolocationRequired();
      final deviceValidationRequired =
          await _tokenStorage.readDeviceValidationRequired();
      return ApiSessionState(
        ApiSessionStatus.authenticated,
        geolocationRequired: geolocationRequired,
        deviceValidationRequired: deviceValidationRequired,
      );
    } on ApiOfflineException {
      return ApiSessionState(
        ApiSessionStatus.offline,
        message: AppErrors.apiUnavailable().userMessage,
      );
    } on ApiUnauthorizedException catch (e) {
      return ApiSessionState(ApiSessionStatus.unauthorized, message: e.message);
    } on ApiAuthenticationException catch (e) {
      return ApiSessionState(ApiSessionStatus.error, message: e.message);
    } on FirebaseSessionException {
      return const ApiSessionState(ApiSessionStatus.unauthenticated);
    } catch (e) {
      debugPrint('Error al restaurar la sesión de API: $e');
      return ApiSessionState(
        ApiSessionStatus.error,
        message:
            const AppException(
              code: 'AUTH-RESTORE',
              message: 'No pudimos validar tu sesión. Inténtalo nuevamente.',
            ).userMessage,
      );
    }
  }

  Future<String> getApiAccessToken({
    required bool forceRefresh,
    String? rejectedToken,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      await _tokenStorage.clearAccessToken();
      throw const FirebaseSessionException();
    }

    final savedToken = await _tokenStorage.readAccessToken();
    if (!forceRefresh && savedToken != null && savedToken.isNotEmpty) {
      return savedToken;
    }

    if (forceRefresh &&
        rejectedToken != null &&
        savedToken != null &&
        savedToken.isNotEmpty &&
        savedToken != rejectedToken) {
      return savedToken;
    }

    final activeRenewal = _tokenRenewal;
    if (activeRenewal != null) return activeRenewal;

    final renewal = _renewApiToken(forceFirebaseRefresh: forceRefresh);
    _tokenRenewal = renewal;
    try {
      return await renewal;
    } finally {
      if (identical(_tokenRenewal, renewal)) {
        _tokenRenewal = null;
      }
    }
  }

  Future<bool> isGeolocationRequired() {
    return _tokenStorage.readGeolocationRequired();
  }

  Future<bool> isDeviceValidationRequired() {
    return _tokenStorage.readDeviceValidationRequired();
  }

  Future<String> _renewApiToken({required bool forceFirebaseRefresh}) async {
    final user = _auth.currentUser;

    if (user == null) {
      await _tokenStorage.clearAccessToken();
      throw const FirebaseSessionException();
    }

    try {
      /*
     * Obtiene el ID Token emitido por Firebase.
     *
     * forceFirebaseRefresh:
     * - true: obliga a Firebase a generar/actualizar el token.
     * - false: puede reutilizar un token vigente.
     */
      final rawFirebaseIdToken = await user.getIdToken(forceFirebaseRefresh);

      if (rawFirebaseIdToken == null || rawFirebaseIdToken.trim().isEmpty) {
        await _clearAllSessions();
        throw const FirebaseSessionException();
      }

      final firebaseIdToken = rawFirebaseIdToken.trim();

      /*
     * Solo durante desarrollo:
     * copia el token completo al portapapeles para usarlo en Postman.
     */
      if (kDebugMode) {
        try {
          await Clipboard.setData(ClipboardData(text: firebaseIdToken));

          debugPrint('==========================================');
          debugPrint('FIREBASE ID TOKEN COPIADO AL PORTAPAPELES');
          debugPrint('Longitud: ${firebaseIdToken.length}');
          debugPrint('Partes JWT: ${firebaseIdToken.split('.').length}');
          debugPrint('==========================================');
        } catch (e) {
          debugPrint('No se pudo copiar el Firebase ID Token: $e');
        }

        /*
       * Muestra aud, iss, email y exp.
       * No imprime nuevamente el token completo.
       */
        _debugFirebaseTokenClaims(firebaseIdToken);
      }

      /*
     * Construye el cuerpo:
     * {
     *   "id_token": "...",
     *   "emp_code": "..."
     * }
     */
      final body = await _firebaseAuthRequestBody(
        user: user,
        firebaseIdToken: firebaseIdToken,
      );

      if (kDebugMode) {
        debugPrint(
          'Enviando autenticación Firebase a: '
          '${ApiConfig.baseUrl}/api/auth/firebase',
        );
      }

      final response = await _apiHttpClient.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/firebase'),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (kDebugMode) {
        debugPrint('Firebase Auth API status: ${response.statusCode}');
        debugPrint('Firebase Auth API response: ${response.body}');
      }

      /*
     * Token Firebase rechazado por Django.
     */
      if (response.statusCode == 401) {
        await _tokenStorage.clearAccessToken();

        final error = AppErrors.firebaseTokenRejected(response.body);

        debugPrint(error.toString());
        throw ApiAuthenticationException(error);
      }

      /*
     * Usuario autenticado, pero sin autorización.
     * Ejemplo: DNI incorrecto o usuario no permitido.
     */
      if (response.statusCode == 403) {
        await _tokenStorage.clearAccessToken();

        final error = AppErrors.authForbidden(response.body);

        debugPrint(error.toString());
        throw ApiUnauthorizedException(error);
      }

      /*
     * Cloudflare, proxy o servidor no disponible.
     */
      if (_isServerUnavailableStatus(response.statusCode)) {
        final error = AppErrors.apiUnavailable(
          technicalDetail: 'HTTP ${response.statusCode}: ${response.body}',
        );

        debugPrint(error.toString());
        throw const ApiOfflineException();
      }

      /*
     * Cualquier otro estado HTTP inesperado.
     */
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = AppErrors.apiAuthUnexpected(
          response.statusCode,
          response.body,
        );

        debugPrint(error.toString());
        throw ApiAuthenticationException(error);
      }

      /*
     * Convierte la respuesta de Django.
     */
      final dynamic decodedResponse;

      try {
        decodedResponse = jsonDecode(response.body);
      } on FormatException catch (e) {
        throw ApiAuthenticationException(
          AppException(
            code: 'AUTH-JSON',
            message:
                'El servidor devolvió una respuesta inválida. '
                'Inténtalo nuevamente.',
            technicalDetail:
                'La respuesta no es JSON válido: $e. '
                'Body: ${response.body}',
          ),
        );
      }

      if (decodedResponse is! Map<String, dynamic>) {
        throw const ApiAuthenticationException(
          AppException(
            code: 'AUTH-RESP',
            message:
                'No pudimos iniciar tu sesión en el servidor '
                'de asistencia. Inténtalo nuevamente.',
            technicalDetail:
                'La respuesta de autenticación no es un objeto JSON.',
          ),
        );
      }

      /*
     * Obtiene el access_token propio de tu API Django.
     */
      final apiAuthResponse = ApiAuthResponse.fromJson(decodedResponse);
      final accessTokenValue = apiAuthResponse.accessToken;

      if (accessTokenValue.trim().isEmpty) {
        throw const ApiAuthenticationException(
          AppException(
            code: 'AUTH-NO-TOKEN',
            message:
                'No pudimos iniciar tu sesión en el servidor '
                'de asistencia. Inténtalo nuevamente.',
            technicalDetail: 'La API no devolvió un access_token válido.',
          ),
        );
      }

      final accessToken = accessTokenValue.trim();

      /*
     * Guarda el token de sesión emitido por Django.
     */
      await _tokenStorage.saveApiSession(
        accessToken: accessToken,
        geolocationRequired: apiAuthResponse.geolocationRequired,
        deviceValidationRequired: apiAuthResponse.deviceValidationRequired,
      );

      if (kDebugMode) {
        debugPrint('Sesión de API creada y access_token guardado.');
      }

      return accessToken;
    } on FirebaseAuthException catch (e) {
      debugPrint(
        'FirebaseAuthException renovando token: '
        '${e.code} - ${e.message}',
      );

      await _clearAllSessions();
      throw const FirebaseSessionException();
    } on SocketException catch (e) {
      debugPrint('SocketException autenticando con la API: $e');

      throw const ApiOfflineException();
    } on http.ClientException catch (e) {
      debugPrint('ClientException autenticando con la API: $e');

      throw const ApiOfflineException();
    }
  }

  Future<Map<String, String>> _firebaseAuthRequestBody({
    required User user,
    required String firebaseIdToken,
  }) async {
    final dni = await _getDniFromEmail(user.email);

    if (dni == null) {
      debugPrint('Auth API sin emp_code: no se encontró DNI para el usuario.');
      throw ApiUnauthorizedException(AppErrors.missingEmpCode());
    }

    debugPrint('Enviando emp_code asociado al usuario para auth API.');
    return {'id_token': firebaseIdToken, 'emp_code': dni};
  }

  bool _isServerUnavailableStatus(int statusCode) {
    return statusCode == 502 ||
        statusCode == 503 ||
        statusCode == 504 ||
        statusCode == 521 ||
        statusCode == 522 ||
        statusCode == 523 ||
        statusCode == 524 ||
        statusCode == 530;
  }

  void _debugFirebaseTokenClaims(String idToken) {
    if (!kDebugMode) return;

    try {
      final parts = idToken.split('.');
      if (parts.length < 2) return;

      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final data = jsonDecode(payload);
      if (data is! Map<String, dynamic>) return;

      debugPrint(
        'Firebase ID Token claims: '
        'aud=${data['aud']}, '
        'iss=${data['iss']}, '
        'email=${data['email']}, '
        'exp=${data['exp']}',
      );
    } catch (e) {
      debugPrint('No se pudieron leer los claims del Firebase ID Token: $e');
    }
  }

  Future<void> _clearAllSessions() async {
    await _tokenStorage.clearAccessToken();
    await _auth.signOut();

    try {
      await _ensureGoogleInitialized();
      await _googleSignIn.signOut();
    } catch (_) {}
  }

  Future<bool> verifyAccessForUser(BuildContext context, User user) async {
    final deviceId = await _getDeviceId();
    final email = user.email?.trim().toLowerCase();

    if (email == null || email.isEmpty) {
      debugPrint('Acceso denegado: Firebase no devolvió correo.');
      await _clearAllSessions();
      return false;
    }

    final docId = _emailToDocId(email);
    final docRef = _db.collection('users').doc(docId);
    final doc = await docRef.get();

    final dni = await _getDniFromEmail(email);

    if (dni == null) {
      debugPrint('Acceso denegado: no existe DNI para $email.');
      if (context.mounted) {
        await showDialog(
          context: context,
          builder:
              (_) => const AlertDialog(
                title: Text('Usuario no registrado'),
                content: Text(
                  'Tu correo no se encuentra asociado a un DNI en el sistema.\n\n'
                  'Por favor, comunícate con el administrador.',
                ),
              ),
        );
      }

      await _clearAllSessions();
      return false;
    }

    final existingData = doc.data();
    final savedDeviceIdValue = existingData?['deviceId'];
    final savedDeviceId =
        savedDeviceIdValue is String ? savedDeviceIdValue.trim() : null;
    final existingPhotoUrl = existingData?['photoUrl'] as String?;
    final newPhotoUrl =
        (user.photoURL != null && user.photoURL!.trim().isNotEmpty)
            ? user.photoURL!.trim()
            : existingPhotoUrl;

    if (!doc.exists || savedDeviceId == null || savedDeviceId.isEmpty) {
      debugPrint('Registrando dispositivo para $email.');
      await docRef.set({
        'email': email,
        'name': user.displayName,
        'deviceId': deviceId,
        'dni': dni,
        'photoUrl': newPhotoUrl,
        'firebaseUid': user.uid,
        'lastLogin': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _showSnack(context, 'Inicio de sesión correcto.');
      return true;
    }

    if (savedDeviceId == deviceId) {
      debugPrint('Dispositivo autorizado para $email.');
      await docRef.update({
        'lastLogin': FieldValue.serverTimestamp(),
        'dni': dni,
        'photoUrl': newPhotoUrl,
        'firebaseUid': user.uid,
      });
      return true;
    }

    debugPrint('Acceso restringido: $email ya tiene otro deviceId registrado.');
    if (context.mounted) {
      await showDialog(
        context: context,
        builder:
            (_) => AlertDialog(
              title: const Text('Acceso restringido'),
              content: const Text(
                'Esta cuenta ya está asociada a otro dispositivo.\n\n'
                'Para usarla en este celular o computadora, '
                'debes comunicarte con el administrador del sistema.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Entendido'),
                ),
              ],
            ),
      );
    }

    await _clearAllSessions();
    return false;
  }
}
