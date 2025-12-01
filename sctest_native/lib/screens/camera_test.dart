import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../camera.dart'; // CORRECTION : Importe camera.dart où se trouve la liste 'cameras'

class CameraTestPage extends StatefulWidget {
  // On ajoute un paramètre pour savoir quelle caméra lancer
  final CameraLensDirection lensDirection; 

  const CameraTestPage({super.key, required this.lensDirection});

  @override
  State<CameraTestPage> createState() => _CameraTestPageState();
}

class _CameraTestPageState extends State<CameraTestPage> {
  CameraController? controller;
  bool isCameraInitialized = false;

  @override
  void initState() {
    super.initState();
    initializeCamera();
  }

  Future<void> initializeCamera() async {
    if (cameras.isEmpty) return;
    
    // 1. On cherche la caméra qui correspond à la direction demandée (Avant ou Arrière)
    CameraDescription selectedCamera;
    try {
      selectedCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == widget.lensDirection,
        orElse: () => cameras[0], // Si pas trouvée, on prend la première par défaut
      );
    } catch (e) {
      // Fallback de sécurité
      selectedCamera = cameras[0];
    }

    // 2. On initialise le contrôleur
    controller = CameraController(selectedCamera, ResolutionPreset.high, enableAudio: false);
    
    try {
      await controller!.initialize();
      if (mounted) {
        setState(() {
          isCameraInitialized = true;
        });
      }
    } catch (e) {
      print("Erreur caméra: $e");
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String titre = widget.lensDirection == CameraLensDirection.front ? "Caméra Avant (Selfie)" : "Caméra Arrière";

    if (!isCameraInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: const Center(child: CircularProgressIndicator(color: Color(0xFF34C759))),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(titre), 
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false, // Pas de bouton retour auto
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white30),
                borderRadius: BorderRadius.circular(12)
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CameraPreview(controller!),
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(30.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, false), // Échec
                  icon: const Icon(Icons.close),
                  label: const Text("DÉFAUT"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15)
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, true), // Succès
                  icon: const Icon(Icons.check),
                  label: const Text("IMAGE OK"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF34C759), 
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15)
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