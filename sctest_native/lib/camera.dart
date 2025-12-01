import 'package:camera/camera.dart';

// Variable globale accessible partout pour stocker la liste des caméras
List<CameraDescription> cameras = [];

// Fonction d'initialisation robuste
Future<void> initCameras() async {
  try {
    // On demande au système la liste des caméras disponibles
    cameras = await availableCameras();
    print("Caméras initialisées : ${cameras.length} trouvées");
  } catch (e) {
    // En cas d'erreur (émulateur, permissions refusées), on ne plante pas l'app
    print("Erreur d'initialisation de la caméra : $e");
    cameras = [];
  }
}