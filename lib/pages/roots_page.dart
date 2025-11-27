// lib/pages/root_page.dart
import 'package:asistenciapersonal1/pages/login_page.dart';
import 'package:asistenciapersonal1/pages/marcacion_asistencia_page.dart';
import 'package:asistenciapersonal1/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class RootPage extends StatelessWidget {
  const RootPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Mientras verifica el estado de FirebaseAuth
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;

        // Si NO hay usuario logueado -> LoginPage
        if (user == null) {
          return const LoginPage();
        }

        // Si hay usuario -> verificar DNI + dispositivo antes de mostrar el mapa
        return FutureBuilder<bool>(
          future: AuthService.instance.verifyAccessForUser(context, user),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              // Verificando acceso...
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final allowed = snap.data ?? false;

            if (allowed) {
              // Dispositivo permitido -> pantalla de marcación
              return const MarcacionAsistenciaPage();
            } else {
              // Acceso bloqueado (sin DNI o en otro dispositivo) ->
              // Firebase ya hizo signOut, volvemos al login.
              return const LoginPage();
            }
          },
        );
      },
    );
  }
}
