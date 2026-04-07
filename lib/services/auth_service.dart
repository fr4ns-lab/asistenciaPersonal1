import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class AuthResult {
  final User user;
  final String? resolvedPhotoUrl;

  AuthResult({required this.user, required this.resolvedPhotoUrl});
}

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();
  static const _deviceIdKey = 'device_id';

  final _uuid = const Uuid();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _googleInitialized = false;

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
    return doc.data()?['dni'] as String?;
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

      final googleAuth = await googleUser.authentication;

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
      _showSnack(context, 'Error al iniciar sesión: $e');
      return null;
    }
  }

  Future<void> signOut(BuildContext context) async {
    try {
      await _ensureGoogleInitialized();

      await _auth.signOut();

      try {
        await _googleSignIn.disconnect();
      } catch (_) {
        try {
          await _googleSignIn.signOut();
        } catch (_) {}
      }

      if (!context.mounted) return;

      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      _showSnack(context, 'Error al cerrar sesión: $e');
    }
  }

  Future<bool> verifyAccessForUser(BuildContext context, User user) async {
    final deviceId = await _getDeviceId();
    final email = user.email?.trim().toLowerCase();

    if (email == null || email.isEmpty) {
      await _auth.signOut();
      try {
        await _googleSignIn.disconnect();
      } catch (_) {}
      return false;
    }

    final docId = _emailToDocId(email);
    final docRef = _db.collection('users').doc(docId);
    final doc = await docRef.get();

    final dni = await _getDniFromEmail(email);

    if (dni == null) {
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

      await _auth.signOut();
      try {
        await _googleSignIn.disconnect();
      } catch (_) {}
      return false;
    }

    final existingData = doc.data();
    final existingPhotoUrl = existingData?['photoUrl'] as String?;
    final newPhotoUrl =
        (user.photoURL != null && user.photoURL!.trim().isNotEmpty)
            ? user.photoURL!.trim()
            : existingPhotoUrl;

    if (!doc.exists || doc.data()?['deviceId'] == null) {
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

    final savedDeviceId = doc.data()!['deviceId'] as String;

    if (savedDeviceId == deviceId) {
      await docRef.update({
        'lastLogin': FieldValue.serverTimestamp(),
        'dni': dni,
        'photoUrl': newPhotoUrl,
        'firebaseUid': user.uid,
      });
      return true;
    }

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

    await _auth.signOut();
    try {
      await _googleSignIn.disconnect();
    } catch (_) {}
    return false;
  }
}
