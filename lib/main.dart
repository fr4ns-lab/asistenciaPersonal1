import 'package:asistenciapersonal1/firebase_options.dart';
import 'package:asistenciapersonal1/pages/roots_page.dart';
import 'package:asistenciapersonal1/theme/app_theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const AsistenciaApp());
}

class AsistenciaApp extends StatelessWidget {
  const AsistenciaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Módulo de asistencia",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const RootPage(),
    );
  }
}
