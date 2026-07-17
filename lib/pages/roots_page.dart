import 'package:asistenciapersonal1/pages/login_page.dart';
import 'package:asistenciapersonal1/pages/main_tabs_page.dart';
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
  String? _sessionUid;
  Future<bool>? _accessFuture;
  Future<ApiSessionState>? _sessionFuture;

  void _refreshConsentCheck() {
    if (!mounted) return;
    setState(() {
      _consentRefreshKey++;
    });
  }

  void _prepareUser(BuildContext context, User user) {
    if (_sessionUid == user.uid && _accessFuture != null) return;
    _sessionUid = user.uid;
    _accessFuture = AuthService.instance.verifyAccessForUser(context, user);
    _sessionFuture = null;
  }

  void _prepareApiSession() {
    _sessionFuture ??= AuthService.instance.restoreApiSession();
  }

  void _retrySession() {
    setState(() {
      _sessionFuture = AuthService.instance.restoreApiSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;

        if (user == null) {
          _sessionUid = null;
          _accessFuture = null;
          _sessionFuture = null;
          return const LoginPage();
        }

        _prepareUser(context, user);
        return FutureBuilder<bool>(
          future: _accessFuture,
          builder: (context, accessSnapshot) {
            if (accessSnapshot.connectionState != ConnectionState.done) {
              return _loadingSession();
            }

            if (!(accessSnapshot.data ?? false)) {
              return const LoginPage();
            }

            _prepareApiSession();
            return FutureBuilder<ApiSessionState>(
              future: _sessionFuture,
              builder: (context, sessionSnapshot) {
                if (sessionSnapshot.connectionState != ConnectionState.done) {
                  return _loadingSession();
                }

                final sessionState =
                    sessionSnapshot.data ??
                    const ApiSessionState(ApiSessionStatus.unauthenticated);
                final status = sessionState.status;
                if (status == ApiSessionStatus.offline) {
                  return _sessionMessage(
                    icon: Icons.cloud_off_rounded,
                    title: 'Servidor no disponible',
                    message:
                        sessionState.message ??
                        'No se pudo validar la sesión con el servidor de asistencia. Revisa tu conexión o inténtalo cuando la API esté disponible.',
                    retry: true,
                  );
                }
                if (status == ApiSessionStatus.unauthorized) {
                  return _sessionMessage(
                    icon: Icons.person_off_rounded,
                    title: 'Acceso no autorizado',
                    message:
                        sessionState.message ??
                        'Tu usuario no está autorizado o fue desactivado. Comunícate con el administrador.',
                  );
                }
                if (status == ApiSessionStatus.error) {
                  return _sessionMessage(
                    icon: Icons.error_outline_rounded,
                    title: 'No se pudo iniciar la sesión',
                    message:
                        sessionState.message ??
                        'El servidor devolvió una respuesta inesperada. Inténtalo nuevamente.',
                    retry: true,
                  );
                }
                if (status == ApiSessionStatus.unauthenticated) {
                  return const LoginPage();
                }

                return FutureBuilder<bool>(
                  key: ValueKey(_consentRefreshKey),
                  future: PrivacyConsentService.instance.hasAcceptedConsent(
                    user,
                  ),
                  builder: (context, consentSnapshot) {
                    if (consentSnapshot.connectionState !=
                        ConnectionState.done) {
                      return _loadingSession();
                    }

                    if (!(consentSnapshot.data ?? false)) {
                      return PrivacyConsentPage(
                        user: user,
                        onAccepted: _refreshConsentCheck,
                      );
                    }

                    return const MainTabsPage();
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _loadingSession() {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Verificando sesión...'),
          ],
        ),
      ),
    );
  }

  Widget _sessionMessage({
    required IconData icon,
    required String title,
    required String message,
    bool retry = false,
  }) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 56, color: const Color(0xFF2563EB)),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                if (retry)
                  FilledButton.icon(
                    onPressed: _retrySession,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Reintentar'),
                  ),
                TextButton(
                  onPressed: () => AuthService.instance.signOut(context),
                  child: const Text('Cerrar sesión'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
