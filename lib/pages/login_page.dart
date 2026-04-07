import 'package:asistenciapersonal1/services/auth_service.dart';
import 'package:flutter/material.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _loading = false;

  String? _name;
  String? _email;
  String? _photo;

  Future<void> _handleGoogleSignIn() async {
    setState(() => _loading = true);

    final result = await AuthService.instance.signInWithGoogle(context);

    if (result != null) {
      final allowed = await AuthService.instance.verifyAccessForUser(
        context,
        result.user,
      );

      if (allowed && mounted) {
        setState(() {
          _name = result.user.displayName;
          _email = result.user.email;
          _photo = result.resolvedPhotoUrl; // <- aquí queda la foto
        });

        Navigator.of(context).pushReplacementNamed('/asistencia');
      }
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLogged = _name != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FF),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: isLogged ? _buildDashboard() : _buildLogin(),
        ),
      ),
    );
  }

  Widget _buildLogin() {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFDCEAFE)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x140F172A),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.fingerprint_rounded,
              size: 54,
              color: Color(0xFF2563EB),
            ),
            const SizedBox(height: 16),
            const Text(
              'Bienvenido',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Inicia sesión con tu cuenta institucional para continuar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _handleGoogleSignIn,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  _loading ? 'Cargando...' : 'Iniciar sesión con Google',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Mi estado',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFDCEAFE)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x140F172A),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: const Color(0xFFEFF6FF),
                    backgroundImage:
                        _photo != null && _photo!.isNotEmpty
                            ? NetworkImage(_photo!)
                            : null,
                    child:
                        (_photo == null || _photo!.isEmpty)
                            ? const Icon(
                              Icons.person,
                              color: Color(0xFF2563EB),
                              size: 32,
                            )
                            : null,
                  ),
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _name ?? '',
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _email ?? '',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
