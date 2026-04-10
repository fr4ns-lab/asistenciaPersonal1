import 'package:asistenciapersonal1/pages/login_page.dart';
import 'package:asistenciapersonal1/pages/marcacion_asistencia_page.dart';
import 'package:asistenciapersonal1/pages/privacy_consent_page.dart';
import 'package:asistenciapersonal1/services/auth_service.dart';
import 'package:asistenciapersonal1/services/privacy_consent_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _consentRefreshKey = 0;

  void _refreshConsentCheck() {
    if (!mounted) return;
    setState(() {
      _consentRefreshKey++;
    });
  }

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

        // Si hay usuario -> verificar DNI + dispositivo
        return FutureBuilder<bool>(
          future: AuthService.instance.verifyAccessForUser(context, user),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final allowed = snap.data ?? false;

            if (!allowed) {
              return const LoginPage();
            }

            // Si está permitido -> verificar autorización
            return FutureBuilder<bool>(
              key: ValueKey(_consentRefreshKey),
              future: PrivacyConsentService.instance.hasAcceptedConsent(user),
              builder: (context, consentSnap) {
                if (consentSnap.connectionState != ConnectionState.done) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }

                final accepted = consentSnap.data ?? false;

                if (!accepted) {
                  return PrivacyConsentPage(
                    user: user,
                    onAccepted: _refreshConsentCheck,
                  );
                }

                return const MarcacionAsistenciaPage();
              },
            );
          },
        );
      },
    );
  }
}
