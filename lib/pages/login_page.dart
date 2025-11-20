import 'package:asistenciapersonal1/services/auth_service.dart';
import 'package:asistenciapersonal1/theme/app_theme.dart';
import 'package:flutter/material.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _loading = false;

  Future<void> _handleGoogleSignIn() async {
    setState(() => _loading = true);

    await AuthService.instance.signInWithGoogle(context);

    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Fondo + contenido
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.primaryDark,
                  AppColors.primary,
                  AppColors.secondary,
                ],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: size.width < 500 ? size.width : 420,
                    ),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 32,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Logo
                            Image.asset(
                              "assets/images/salle.png",
                              height: size.height / 8,
                              width: size.width * 0.45,
                              fit: BoxFit.cover,
                            ),
                            const SizedBox(height: 16),

                            // Título
                            Text(
                              "Módulo de asistencia",
                              textAlign: TextAlign.center,
                              style: textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),

                            // Subtítulo
                            Text(
                              "Inicia sesión con tu cuenta institucional "
                              "para registrar tu asistencia.",
                              textAlign: TextAlign.center,
                              style: textTheme.bodyMedium,
                            ),

                            const SizedBox(height: 28),

                            // Botón Google
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed:
                                    _loading
                                        ? null
                                        : () => _handleGoogleSignIn(),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (!_loading)
                                      const CircleAvatar(
                                        radius: 14,
                                        backgroundImage: AssetImage(
                                          "assets/images/google.png",
                                        ),
                                        backgroundColor: Colors.transparent,
                                      ),
                                    if (!_loading) const SizedBox(width: 10),
                                    Text(
                                      _loading
                                          ? "Iniciando sesión..."
                                          : "Inicia sesión con Google",
                                      style: textTheme.labelLarge?.copyWith(
                                        color: Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 20),

                            // Pie de página
                            Text(
                              "Colegio La Salle • Arequipa",
                              style: textTheme.bodyMedium?.copyWith(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Overlay de carga
          if (_loading)
            Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.black45,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
