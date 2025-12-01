import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Pour les réglages système
import 'camera.dart'; // On importe notre nouveau gestionnaire de caméra
import 'screens/control_screen.dart'; // On importe l'écran principal

Future<void> main() async {
  // 1. Initialisation du moteur Flutter
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. Initialisation des modules externes (Caméra)
  // On appelle la fonction qu'on vient de créer dans camera.dart
  await initCameras();
  
  // 3. Lancement de l'application
  runApp(const SCtestApp());
}

class SCtestApp extends StatelessWidget {
  const SCtestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SCtest Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: const Color(0xFF34C759),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
        ),
      ),
      // On dirige vers le tableau de bord
      home: const ControlScreen(),
    );
  }
}