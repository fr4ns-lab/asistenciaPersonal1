import 'package:asistenciapersonal1/services/auth_service.dart';
import 'package:asistenciapersonal1/pages/device_renewal_admin_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.manageDeviceAuthorizations});

  final bool manageDeviceAuthorizations;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final photoUrl = user?.photoURL;
    final name = user?.displayName?.trim();
    final email = user?.email?.trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text('Perfil'),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: const Color(0xFFEFF6FF),
                  backgroundImage:
                      photoUrl == null || photoUrl.isEmpty
                          ? null
                          : NetworkImage(photoUrl),
                  child:
                      photoUrl == null || photoUrl.isEmpty
                          ? const Icon(
                            Icons.person_rounded,
                            color: Color(0xFF2563EB),
                            size: 34,
                          )
                          : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name == null || name.isEmpty ? 'Usuario' : name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email == null || email.isEmpty ? 'Sin correo' : email,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.verified_user_rounded),
                  title: const Text('Sesión protegida'),
                  // subtitle: const Text('Google, Firebase y token interno API'),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 6,
                  ),
                ),
                const Divider(height: 1),
                if (manageDeviceAuthorizations) ...[
                  ListTile(
                    leading: const Icon(Icons.admin_panel_settings_rounded),
                    title: const Text('Administrar dispositivos'),
                    subtitle: const Text('Autorizar cambios de dispositivo'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap:
                        () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const DeviceRenewalAdminPage(),
                          ),
                        ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 6,
                    ),
                  ),
                  const Divider(height: 1),
                ],
                ListTile(
                  leading: const Icon(
                    Icons.logout_rounded,
                    color: Color(0xFFDC2626),
                  ),
                  title: const Text('Cerrar sesión'),
                  textColor: const Color(0xFFDC2626),
                  iconColor: const Color(0xFFDC2626),
                  onTap: () => AuthService.instance.signOut(context),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
