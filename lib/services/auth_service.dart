// lib/services/auth_service.dart
import 'dart:io';

import 'package:asistenciapersonal1/pages/home_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
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

  // ✅ v7.2.0: se usa el singleton
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  bool _googleInitialized = false;

  Future<String?> _getDniFromEmail(String? email) async {
    if (email == null || email.isEmpty) return null;

    final normalized = email.toLowerCase().trim();

    final doc = await _db.collection('dni_by_email').doc(normalized).get();
    if (!doc.exists) return null;

    final data = doc.data();
    return data?['dni'] as String?;
  }

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

      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      final userCred = await _auth.signInWithCredential(credential);
      final user = userCred.user;

      if (user == null) {
        _showSnack(context, 'No se pudo obtener el usuario de Firebase.');
        return;
      }

      // 🔴🔴🔴 VALIDAR DOMINIO AQUÍ 🔴🔴🔴
      const allowedDomain = 'lasalle.edu.pe';

      final email = user.email ?? '';
      final domain = email.split('@').length == 2 ? email.split('@')[1] : '';

      if (domain.toLowerCase() != allowedDomain.toLowerCase()) {
        // Opcional: borrar el usuario recién creado en Firebase Auth
        try {
          await user.delete();
        } catch (_) {
          // si falla delete, igual cerramos sesión
        }

        // cerrar sesión en Firebase y Google
        await _auth.signOut();
        await _googleSignIn.disconnect();

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

        return; // 🚫 no seguimos a _enforceSingleDevice
      }

      // ✅ Si el dominio es válido, seguimos con la lógica de 1 solo dispositivo
      await _enforceSingleDevice(context, user);
    } catch (e) {
      _showSnack(context, 'Error al iniciar sesión: $e');
    }
  }

  Future<void> _enforceSingleDevice(BuildContext context, User user) async {
    final deviceId = await _getDeviceId();
    final docRef = _db.collection('users').doc(user.uid);
    final doc = await docRef.get();
    // 🔹 Buscar DNI por correo
    final dni = await _getDniFromEmail(user.email);
    if (dni == null) {
      await _auth.signOut();
      await _googleSignIn.disconnect();

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
      return;
    }

    if (!doc.exists || doc.data()?['deviceId'] == null) {
      // Primera vez: asociar este dispositivo
      await docRef.set({
        'email': user.email,
        'name': user.displayName,
        'deviceId': deviceId,
        'dni': dni, // 👈 guardamos el DNI
        'lastLogin': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _showSnack(context, 'Inicio de sesión correcto.');
      _navigateToHome(context);
      return;
    }

    final savedDeviceId = doc.data()!['deviceId'] as String;

    if (savedDeviceId == deviceId) {
      // Mismo dispositivo -> permitir
      await docRef.update({
        'lastLogin': FieldValue.serverTimestamp(),
        'dni': dni, // por si actualizaste el mapeo
      });
      _showSnack(context, 'Bienvenido nuevamente.');
      _navigateToHome(context);
    } else {
      // Otro dispositivo -> BLOQUEAR
      await _auth.signOut();
      await _googleSignIn.disconnect();

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
    }
  }

  Future<String> _getDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Si ya tengo un ID guardado, lo uso
      final saved = prefs.getString(_deviceIdKey);
      if (saved != null && saved.isNotEmpty) {
        return saved;
      }

      // 2. Si no existe, genero uno nuevo y lo guardo
      final newId = _uuid.v4();
      await prefs.setString(_deviceIdKey, newId);
      return newId;
    } catch (_) {
      // Si algo falla, genero uno “temporal” (no persistente)
      return 'temp_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  void _navigateToHome(BuildContext context) {
    // TODO: reemplaza por tu pantalla principal
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
    );
  }

  void _showSnack(BuildContext context, String message) {
    if (!context.mounted) return;
    print(message);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
