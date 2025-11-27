// lib/services/auth_service.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class AuthService {
  AuthService._();
  static const _deviceIdKey = 'device_id';
  final _uuid = const Uuid();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _googleInitialized = false;

  // ==================== HELPERS ====================

  Future<String?> _getDniFromEmail(String? email) async {
    if (email == null || email.isEmpty) return null;

    final normalized = email.toLowerCase().trim();

    final doc = await _db.collection('dni_by_email').doc(normalized).get();
    if (!doc.exists) return null;

    final data = doc.data();
    return data?['dni'] as String?;
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

  void _showSnack(BuildContext context, String message) {
    if (!context.mounted) return;
    debugPrint(message);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ==================== LOGIN CON GOOGLE ====================

  Future<void> signInWithGoogle(BuildContext context) async {
    try {
      if (!_googleInitialized) {
        await _googleSignIn.initialize();
        _googleInitialized = true;
      }

      GoogleSignInAccount? googleUser;

      if (_googleSignIn.supportsAuthenticate()) {
        googleUser = await _googleSignIn.authenticate();
      } else {
        throw Exception(
          'Este dispositivo no soporta authenticate(); revisa la config de GoogleSignIn.',
        );
      }

      if (googleUser == null) {
        _showSnack(context, 'Inicio de sesión cancelado.');
        return;
      }

      // ⚠️ VALIDAR DOMINIO ANTES DE IR A FIREBASE
      const allowedDomain = 'lasalle.edu.pe';
      final email = googleUser.email;
      final domain = email.split('@').length == 2 ? email.split('@')[1] : '';

      if (domain.toLowerCase() != allowedDomain.toLowerCase()) {
        if (context.mounted) {
          await showDialog(
            context: context,
            builder:
                (_) => AlertDialog(
                  title: const Text('Dominio no permitido'),
                  content: Text(
                    'Solo se permiten cuentas de $allowedDomain.\n\n'
                    'Tu correo actual es: $email',
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

        await _googleSignIn.disconnect();
        return;
      }

      // 👉 Si el dominio es válido recién ahora vamos a FirebaseAuth
      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      await _auth.signInWithCredential(credential);
      // A partir de aquí, RootPage se entera de que hay usuario y hará
      // verifyAccessForUser(user) antes de mostrar la pantalla de marcación.
    } catch (e) {
      _showSnack(context, 'Error al iniciar sesión: $e');
    }
  }

  // ==================== VERIFICAR ACCESO (DNI + DISPOSITIVO) ====================

  /// Devuelve true si el usuario puede usar la app en este dispositivo.
  /// Devuelve false si se bloquea (sin DNI o en otro dispositivo).
  Future<bool> verifyAccessForUser(BuildContext context, User user) async {
    final deviceId = await _getDeviceId();
    final docRef = _db.collection('users').doc(user.uid);
    final doc = await docRef.get();

    // 1) Buscar DNI
    final dni = await _getDniFromEmail(user.email);
    if (dni == null) {
      // 🔹 Primero mostramos el mensaje
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

      // 🔹 Luego cerramos sesión
      await _auth.signOut();
      await _googleSignIn.disconnect();

      return false;
    }

    // 2) Primera vez o sin deviceId -> asociar este dispositivo
    if (!doc.exists || doc.data()?['deviceId'] == null) {
      await docRef.set({
        'email': user.email,
        'name': user.displayName,
        'deviceId': deviceId,
        'dni': dni,
        'lastLogin': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _showSnack(context, 'Inicio de sesión correcto.');
      return true;
    }

    final savedDeviceId = doc.data()!['deviceId'] as String;

    // 3) Mismo dispositivo -> permitir
    if (savedDeviceId == deviceId) {
      await docRef.update({
        'lastLogin': FieldValue.serverTimestamp(),
        'dni': dni,
      });
      _showSnack(context, 'Bienvenido nuevamente.');
      return true;
    }

    // 4) Otro dispositivo -> BLOQUEAR
    // 🔹 Primero mostramos el mensaje
    if (context.mounted) {
      await showDialog(
        context: context,
        builder:
            (_) => AlertDialog(
              title: const Text('Acceso restringido'),
              content: const Text(
                'Esta cuenta ya está asociada a otro dispositivo.\n\n'
                'Para usarla en este celular/computadora, '
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

    // 🔹 Luego cerramos sesión
    await _auth.signOut();
    await _googleSignIn.disconnect();

    return false;
  }
}
