import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'globals.dart';
import 'screens/control_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    print("Erreur Caméra: $e");
  }
  runApp(const SCtestApp());
}

class SCtestApp extends StatelessWidget {
    const SCtestApp({super.key});

    @override
    Widget build(BuildContext context) {
        return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark().copyWith(
                scaffoldBackgroundColor: const Color(0xFF121212), 
                primaryColor: const Color(0xFF34C759)
            ),
            home: const ControlScreen(),
        );
    }
}