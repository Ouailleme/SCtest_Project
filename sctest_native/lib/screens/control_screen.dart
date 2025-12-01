import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';
import 'package:camera/camera.dart'; 
import 'package:local_auth/local_auth.dart';

import '../globals.dart';
import 'screen_test.dart';
import 'button_test.dart';
import 'sensor_test.dart';
import 'camera_test.dart';

class ControlScreen extends StatefulWidget {
    const ControlScreen({super.key});
    @override
    State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
    static const platform = MethodChannel('com.example.sctest/native');
    
    Socket? socket;
    bool isConnected = false;
    String statusMessage = "Recherche PC...";
    Color statusColor = Colors.orange;
    Timer? reconnectTimer;
    
    String audioStatusMessage = "Prêt."; 
    bool isAudioTesting = false; 
    bool isFlashOn = false; 
    
    // Stocke les résultats des tests (true = OK, false = KO, null = Pas testé)
    Map<String, bool?> testsPassed = {}; 

    // --- BIOMÉTRIE ---
    final LocalAuthentication auth = LocalAuthentication();
    String biometricStatusMessage = "Prêt.";
    bool isBiometricTesting = false;

    @override
    void initState() {
        super.initState();
        connectToPC();
        reconnectTimer = Timer.periodic(const Duration(seconds: 3), (t) {
            if (!isConnected) connectToPC();
        });
        
        platform.setMethodCallHandler((call) async {
            if (call.method == "onButtonEvent") {
                if (onGlobalNativeEvent != null) {
                    onGlobalNativeEvent!(call.arguments as String);
                }
            }
        });
    }

    @override
    void dispose() {
        reconnectTimer?.cancel();
        socket?.close();
        super.dispose();
    }

    void connectToPC() async {
        try {
            socket = await Socket.connect('127.0.0.1', 16000, timeout: const Duration(seconds: 2));
            if (mounted) setState(() { isConnected = true; statusMessage = "Connecté au PC"; statusColor = const Color(0xFF34C759); });
            socket!.listen((data) => handleCommand(String.fromCharCodes(data).trim()), onDone: disconnect, onError: (e) => disconnect());
            safeSocketWrite("HELLO_FROM_ANDROID\n");
        } catch (e) { disconnect(); }
    }

    void disconnect() {
        if (mounted) setState(() { isConnected = false; statusMessage = "PC Déconnecté"; statusColor = Colors.red; socket?.close(); });
    }

    void safeSocketWrite(String data) {
        if (isConnected && socket != null) socket!.write(data);
    }

    void handleCommand(String cmd) async {
        if (cmd.contains("ECRAN")) await launchScreenTest();
        if (cmd.contains("HP_ECOUTEUR")) await testSpeaker('EARPIECE');
        if (cmd.contains("HP_BAS")) await testSpeaker('MEDIA');
        if (cmd.contains("FLASH")) await toggleFlash();
        if (cmd.contains("VIBREUR")) await nativeVibrate();
        if (cmd.contains("MIC_AVANT")) await testMicrophone('FRONT');
        if (cmd.contains("MIC_ARRIERE")) await testMicrophone('BACK');
        if (cmd.contains("BOUTONS_VOL")) await launchButtonTest();
        if (cmd.contains("ACCEL")) await launchSensorTest("ACCEL");
        if (cmd.contains("PROXIMITE")) await launchSensorTest("PROXIMITY");
        
        // --- COMMANDES CAMÉRAS ---
        if (cmd.contains("CAMERA_AV")) await launchCameraTest(CameraLensDirection.front);
        if (cmd.contains("CAMERA_ARR")) await launchCameraTest(CameraLensDirection.back);

        if (cmd.startsWith("TEST_VALIDATED:")) {
            final parts = cmd.split(':');
            if (parts.length == 3) {
                final testName = parts[1];
                final result = parts[2] == 'OK';
                String displayName = testName;
                // Mapping pour l'affichage
                if (testName == 'HP_BAS') displayName = 'HP Bas (Média)';
                if (testName == 'HP_ECOUTEUR') displayName = 'HP Écouteur';
                if (testName == 'CAMERA_AV') displayName = 'Caméra Av.';
                if (testName == 'CAMERA_ARR') displayName = 'Caméra Arr.';
                
                setState(() { testsPassed[displayName] = result; });
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$displayName : ${result ? 'OK' : 'KO'}"), backgroundColor: result ? Colors.green : Colors.red));
            }
        }
    }

    // --- FONCTION TEST CAMERA (AVEC DIRECTION) ---
    // CORRECTION : void -> Future<void> pour permettre le await
    Future<void> launchCameraTest(CameraLensDirection direction) async {
        final result = await Navigator.push(
            context, 
            MaterialPageRoute(builder: (context) => CameraTestPage(lensDirection: direction))
        );
        
        String cmdCode = (direction == CameraLensDirection.front) ? "CAMERA_AV" : "CAMERA_ARR";
        String testName = (direction == CameraLensDirection.front) ? "Caméra Av." : "Caméra Arr.";

        if (result == true) {
            safeSocketWrite("TEST_${cmdCode}_OK\n");
            setState(() { testsPassed[testName] = true; });
        } else {
             safeSocketWrite("TEST_${cmdCode}_FAIL\n");
             setState(() { testsPassed[testName] = false; });
        }
    }

    // CORRECTION : void -> Future<void>
    Future<void> launchSensorTest(String type) async {
        final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => SensorTestPage(sensorType: type)));
        String testName = (type == "ACCEL") ? "Accéléromètre" : "Proximité";
        String cmdCode = (type == "ACCEL") ? "ACCEL" : "PROXIMITE";
        if (result == true) {
            safeSocketWrite("TEST_${cmdCode}_OK\n");
            setState(() { testsPassed[testName] = true; });
        } else {
            safeSocketWrite("TEST_${cmdCode}_FAIL\n");
            setState(() { testsPassed[testName] = false; });
        }
    }

    // --- FONCTION TEST BIOMÉTRIQUE ---
    Future<void> launchBiometricTest() async {
            if (!mounted || isBiometricTesting) return;
            setState(() { isBiometricTesting = true; biometricStatusMessage = "Vérification biométrie..."; });
            bool canCheckBiometrics = false;
            bool authenticated = false;
            try {
                canCheckBiometrics = await auth.canCheckBiometrics;
                if (!canCheckBiometrics) {
                    setState(() {
                        biometricStatusMessage = "Biométrie non disponible sur cet appareil.";
                        testsPassed['Biométrie'] = false;
                    });
                    safeSocketWrite("TEST_BIOMETRIE_FAIL\n");
                    return;
                }
                final List<BiometricType> availableBiometrics = await auth.getAvailableBiometrics();
                if (availableBiometrics.isEmpty) {
                    setState(() {
                        biometricStatusMessage = "Aucun capteur biométrique détecté.";
                        testsPassed['Biométrie'] = false;
                    });
                    safeSocketWrite("TEST_BIOMETRIE_FAIL\n");
                    return;
                }
                setState(() { biometricStatusMessage = "Authentification..."; });
                authenticated = await auth.authenticate(
                    localizedReason: 'Veuillez vous authentifier',
                    options: const AuthenticationOptions(
                        useErrorDialogs: true,
                        stickyAuth: true,
                    ),
                );
                setState(() {
                    biometricStatusMessage = authenticated ? "✅ Succès biométrique !" : "❌ Échec biométrie.";
                    testsPassed['Biométrie'] = authenticated;
                });
                safeSocketWrite("TEST_BIOMETRIE_" + (authenticated ? "OK" : "FAIL") + "\n");
            } catch (e) {
                setState(() {
                    biometricStatusMessage = "Erreur: $e";
                    testsPassed['Biométrie'] = false;
                });
                safeSocketWrite("TEST_BIOMETRIE_FAIL\n");
            } finally {
                setState(() { isBiometricTesting = false; });
            }
    }

    // CORRECTION : void -> Future<void>
    Future<void> launchScreenTest() async {
        final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const ScreenTestPage()));
        if (result == true) {
            safeSocketWrite("TEST_ECRAN_OK\n");
            setState(() { testsPassed['Écran'] = true; });
        } else {
            safeSocketWrite("TEST_ECRAN_FAIL\n");
            // Optionnel : marquer comme échoué explicitement
            setState(() { testsPassed['Écran'] = false; }); 
        }
    }
    
    // CORRECTION : void -> Future<void>
    Future<void> launchButtonTest() async {
        final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const ButtonTestPage()));
        String testName = 'Boutons Vol';
        if (result == true) {
            safeSocketWrite("TEST_BOUTONS_VOL_OK\n");
            setState(() { testsPassed[testName] = true; });
        } else {
             safeSocketWrite("TEST_BOUTONS_VOL_FAIL\n");
             setState(() { testsPassed[testName] = false; });
        }
    }

    Future<void> toggleFlash() async {
        bool newState = !isFlashOn;
        try {
            await platform.invokeMethod('toggleFlash', newState);
            setState(() { isFlashOn = newState; testsPassed['Flash'] = true; });
            safeSocketWrite("TEST_FLASH_OK\n");
        } catch (e) { safeSocketWrite("TEST_FLASH_FAIL\n"); testsPassed['Flash'] = false; }
    }

    Future<void> nativeVibrate() async {
        try {
            await platform.invokeMethod('vibrate');
            setState(() { testsPassed['Vibreur'] = true; });
            safeSocketWrite("TEST_VIBREUR_OK\n");
        } catch (e) { safeSocketWrite("TEST_VIBREUR_FAIL\n"); testsPassed['Vibreur'] = false; }
    }
    
    Future<void> testMicrophone(String micType) async {
        if (!mounted || isAudioTesting) return;
        final String name = micType == 'FRONT' ? 'Micro Avant' : 'Micro Arr.';
        final String commandName = micType == 'FRONT' ? 'MIC_AVANT' : 'MIC_ARRIERE';
        try {
            setState(() { isAudioTesting = true; audioStatusMessage = "Autorisation..."; });
            final bool? granted = await platform.invokeMethod('requestMicPermission');
            if (granted != true) {
                setState(() { testsPassed[name] = false; audioStatusMessage = "Refusé"; });
                safeSocketWrite("TEST_${commandName}_FAIL\n"); 
                return;
            }
            setState(() { audioStatusMessage = "🔴 Parlez fort ($name)..."; });
            final bool? soundDetected = await platform.invokeMethod('startMonitoringRecording', micType);
            if (soundDetected == true) {
                safeSocketWrite("TEST_${commandName}_OK\n"); 
                setState(() { testsPassed[name] = true; audioStatusMessage = "✅ Succès !"; });
            } else {
                safeSocketWrite("TEST_${commandName}_FAIL\n"); 
                setState(() { testsPassed[name] = false; audioStatusMessage = "❌ Échec."; });
            }
        } catch (e) { safeSocketWrite("TEST_${commandName}_FAIL\n"); } 
        finally { if (mounted) setState(() { isAudioTesting = false; }); }
    }

    Future<void> testSpeaker(String speakerType) async {
        if (!mounted || isAudioTesting) return;
        final String name = speakerType == 'MEDIA' ? 'HP Bas (Média)' : 'HP Écouteur';
        final String commandName = speakerType == 'MEDIA' ? 'HP_BAS' : 'HP_ECOUTEUR'; 
        setState(() { isAudioTesting = true; audioStatusMessage = "🔊 Test $name..."; });
        try {
            await platform.invokeMethod('playToneOnSpeaker', speakerType);
            
            // On attend un peu que le son joue
            await Future.delayed(const Duration(milliseconds: 1500));
            safeSocketWrite("TRIGGERED:${commandName}\n"); 
            
            setState(() { audioStatusMessage = "Validez sur le PC"; });
            
            // CORRECTION CRITIQUE : on attend la réponse de la boite de dialogue
            await showMobileValidationDialog(name);
            
        } catch (e) { safeSocketWrite("TEST_${commandName}_FAIL\n"); } 
        finally { setState(() { isAudioTesting = false; }); }
    }
    
    // CORRECTION : Retourne un Future pour que testSpeaker puisse attendre
    Future<void> showMobileValidationDialog(String testName) {
        // CORRECTION : On retourne le résultat de showDialog
        return showDialog(
            context: context, barrierDismissible: false,
            builder: (BuildContext context) {
                return AlertDialog(
                    title: Text("Test : $testName"), content: const Text("Entendez-vous le son ?"),
                    actions: <Widget>[
                        TextButton(onPressed: () {
                                String cleanedName = testName.toUpperCase().replaceAll(" ", "_").replaceAll("É", "E").replaceAll("(", "").replaceAll(")", "");
                                safeSocketWrite("TEST_${cleanedName}_OK\n");
                                setState(() { testsPassed[testName] = true; });
                                Navigator.of(context).pop();
                            }, child: const Text('✅ OUI', style: TextStyle(color: Colors.green))),
                        TextButton(onPressed: () {
                                String cleanedName = testName.toUpperCase().replaceAll(" ", "_").replaceAll("É", "E").replaceAll("(", "").replaceAll(")", "");
                                safeSocketWrite("TEST_${cleanedName}_FAIL\n");
                                setState(() { testsPassed[testName] = false; });
                                Navigator.of(context).pop();
                            }, child: const Text('❌ NON', style: TextStyle(color: Colors.red))),
                    ],
                );
            },
        );
    }
    
    @override
    Widget build(BuildContext context) {
        final List<Map<String, dynamic>> tests = [
            {'icon': Icons.volume_up, 'name': 'HP Écouteur', 'action': () => testSpeaker('EARPIECE')},
            {'icon': Icons.volume_down, 'name': 'HP Bas (Média)', 'action': () => testSpeaker('MEDIA')},
            {'icon': Icons.mic_external_on, 'name': 'Micro Avant', 'action': () => testMicrophone('FRONT')},
            {'icon': Icons.mic_external_off, 'name': 'Micro Arr.', 'action': () => testMicrophone('BACK')},
            {'icon': Icons.aspect_ratio, 'name': 'Écran', 'action': launchScreenTest},
            {'icon': Icons.flashlight_on, 'name': 'Flash', 'action': toggleFlash},
            {'icon': Icons.vibration, 'name': 'Vibreur', 'action': nativeVibrate},
            {'icon': Icons.power_settings_new, 'name': 'Boutons Vol', 'action': launchButtonTest}, 
            {'icon': Icons.screen_rotation, 'name': 'Accéléromètre', 'action': () => launchSensorTest("ACCEL")}, 
            {'icon': Icons.sensors, 'name': 'Proximité', 'action': () => launchSensorTest("PROXIMITY")},
            {'icon': Icons.camera_front, 'name': 'Caméra Av.', 'action': () => launchCameraTest(CameraLensDirection.front)},
            {'icon': Icons.camera_alt, 'name': 'Caméra Arr.', 'action': () => launchCameraTest(CameraLensDirection.back)},
            {'icon': Icons.touch_app, 'name': 'Tactile', 'action': (){}},
            {'icon': Icons.fingerprint, 'name': 'Biométrie', 'action': launchBiometricTest},
        ];

        // --- DIAGNOSTIC COMPLET CORRIGÉ ---
        Future<void> runFullDiagnostic() async {

              // On réinitialise éventuellement les résultats si on veut (optionnel)
              // testsPassed.clear(); 

              await testSpeaker('EARPIECE'); // Attend maintenant le clic utilisateur
              // Note: testsPassed est mis à jour DANS testSpeaker, donc pas besoin de le refaire ici manuellement 
              // sauf si on veut consolider une liste locale 'results'.

              await testSpeaker('MEDIA');

              await testMicrophone('FRONT');

              await testMicrophone('BACK');

              await launchScreenTest(); 

              await toggleFlash();

              await nativeVibrate();

              await launchButtonTest();

              await launchSensorTest("ACCEL");

              await launchSensorTest("PROXIMITY");

              await launchCameraTest(CameraLensDirection.front);

              await launchCameraTest(CameraLensDirection.back);

              await launchBiometricTest();

            // Envoi des résultats au PC
            String rapport = testsPassed.entries.map((e) =>
              '${e.key}:${e.value == true ? 'OK' : (e.value == false ? 'KO' : 'NON_TESTE')}'
            ).join(';');
            safeSocketWrite('DIAGNOSTIC_RAPPORT:' + rapport + '\n');

            // Affichage du récapitulatif local
            showDialog(
                context: context,
                builder: (context) {
                    return AlertDialog(
                        title: const Text('Rapport diagnostic complet'),
                        content: SingleChildScrollView(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: testsPassed.entries.map((e) => Text(
                                    '${e.key} : ${e.value == true ? '✅ OK' : (e.value == false ? '❌ KO' : '⏺ Non testé')}',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: e.value == true ? Colors.green : (e.value == false ? Colors.red : Colors.orange)
                                    ),
                                )).toList(),
                            ),
                        ),
                        actions: [
                            TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Fermer')
                            ),
                        ],
                    );
                }
            );
        }

                return Scaffold(
                    appBar: AppBar(
                        title: const Text("SCtest Mobile Pro"),
                        centerTitle: true,
                        backgroundColor: Colors.transparent,
                        elevation: 0,
                    ),
                    body: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                            children: [
                                SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                        icon: const Icon(Icons.medical_services),
                                        label: const Text('Diagnostic complet'),
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                                        onPressed: () async {
                                            await runFullDiagnostic();
                                        },
                                    ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                    padding: const EdgeInsets.symmetric(vertical: 20),
                                    decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(16), border: Border.all(color: statusColor, width: 2)),
                                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                        Icon(isConnected ? Icons.link : Icons.link_off, color: statusColor),
                                        const SizedBox(width: 10),
                                        Text(statusMessage, style: TextStyle(color: statusColor, fontSize: 16, fontWeight: FontWeight.bold))
                                    ]),
                                ),
                                const SizedBox(height: 10),
                                Text(audioStatusMessage, style: TextStyle(color: isAudioTesting ? Colors.orange : Colors.white70, fontSize: 14)),
                                const SizedBox(height: 5),
                                Text(biometricStatusMessage, style: TextStyle(color: isBiometricTesting ? Colors.orange : Colors.white70, fontSize: 14)),
                                const SizedBox(height: 10),
                                Expanded(
                                    child: GridView.builder(
                                        itemCount: tests.length,
                                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10),
                                        itemBuilder: (context, index) {
                                            String name = tests[index]['name'];
                                            bool? testResult = testsPassed[name];
                                            Color cardColor = testResult == true ? const Color(0xFF34C759) : (testResult == false ? const Color(0xFFFF3B30) : const Color(0xFF252525));
                                            return InkWell(
                                                onTap: isAudioTesting ? null : tests[index]['action'],
                                                child: Container(
                                                    decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12)),
                                                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                                        Icon(tests[index]['icon'], color: Colors.white, size: 30),
                                                        const SizedBox(height: 5),
                                                        Text(name, style: const TextStyle(color: Colors.white, fontSize: 12))
                                                    ]),
                                                ),
                                            );
                                        },
                                    ),
                                ),
                            ],
                        ),
                    ),
                );
    }
}