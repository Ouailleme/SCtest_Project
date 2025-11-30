import 'package:camera/camera.dart';

// Variable globale pour faire passer les événements natifs (Boutons, Capteurs) vers l'interface active
Function(String)? onGlobalNativeEvent;

// Variable globale pour les caméras (initialisée au démarrage)
List<CameraDescription> cameras = [];