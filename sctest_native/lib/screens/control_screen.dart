import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';
import '../globals.dart'; // Import des globales
import 'screen_test.dart';
import 'button_test.dart';
import 'sensor_test.dart'; // On va créer ce fichier

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
    
    Map<String, bool?> testsPassed = {}; 

    @override
    void initState() {
        super.initState();
        connectToPC();
        reconnectTimer = Timer.periodic(const Duration(seconds: 3), (t) {
            if (!isConnected) connectToPC();
        });
        
        // ÉCOUTEUR PRINCIPAL
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
            socket = await Socket.connect('127.0.0.1', 6000, timeout: const Duration(seconds: 2));
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
        if (cmd.contains("ECRAN")) launchScreenTest();
        if (cmd.contains("HP_ECOUTEUR")) testSpeaker('EARPIECE');
        if (cmd.contains("HP_BAS")) testSpeaker('MEDIA');
        if (cmd.contains("FLASH")) toggleFlash();
        if (cmd.contains("VIBREUR")) nativeVibrate();
        if (cmd.contains("MIC_AVANT")) testMicrophone('FRONT');
        if (cmd.contains("MIC_ARRIERE")) testMicrophone('BACK');
        if (cmd.contains("BOUTONS_VOL")) launchButtonTest();
        if (cmd.contains("ACCEL")) launchSensorTest("ACCEL");
        if (cmd.contains("PROXIMITE")) launchSensorTest("PROXIMITY");

        if (cmd.startsWith("TEST_VALIDATED:")) {
            final parts = cmd.split(':');
            if (parts.length == 3) {
                final testName = parts[1];
                final result = parts[2] == 'OK';
                String displayName = testName;
                if (testName == 'HP_BAS') displayName = 'HP Bas (Média)';
                if (testName == 'HP_ECOUTEUR') displayName = 'HP Écouteur';
                setState(() { testsPassed[displayName] = result; });
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$displayName : ${result ? 'OK' : 'KO'}"), backgroundColor: result ? Colors.green : Colors.red));
            }
        }
    }

    // --- FONCTIONS DE TEST ---
    void launchSensorTest(String type) async {
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

    Future<void> toggleFlash() async {
        bool newState = !isFlashOn;
        try {
            await platform.invokeMethod('toggleFlash', newState);
            setState(() { isFlashOn = newState; testsPassed['Flash'] = true; });
            safeSocketWrite("TEST_FLASH_OK\n");
        } catch (e) { safeSocketWrite("TEST_FLASH_FAIL\n"); }
    }

    Future<void> nativeVibrate() async {
        try {
            await platform.invokeMethod('vibrate');
            setState(() { testsPassed['Vibreur'] = true; });
            safeSocketWrite("TEST_VIBREUR_OK\n");
        } catch (e) { safeSocketWrite("TEST_VIBREUR_FAIL\n"); }
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
        } catch (e) {
            safeSocketWrite("TEST_${commandName}_FAIL\n");
            setState(() { testsPassed[name] = false; audioStatusMessage = "Erreur Test"; });
        } finally {
            if (mounted) setState(() { isAudioTesting = false; });
        }
    }

    Future<void> testSpeaker(String speakerType) async {
        if (!mounted || isAudioTesting) return;
        final String name = speakerType == 'MEDIA' ? 'HP Bas (Média)' : 'HP Écouteur';
        final String commandName = speakerType == 'MEDIA' ? 'HP_BAS' : 'HP_ECOUTEUR'; 
        setState(() { isAudioTesting = true; audioStatusMessage = "🔊 Test $name..."; });
        try {
            await platform.invokeMethod('playToneOnSpeaker', speakerType);
            await Future.delayed(const Duration(milliseconds: 1500));
            safeSocketWrite("TRIGGERED:${commandName}\n"); 
            setState(() { audioStatusMessage = "Validez sur le PC"; });
            showMobileValidationDialog(name);
        } catch (e) { safeSocketWrite("TEST_${commandName}_FAIL\n"); } 
        finally { setState(() { isAudioTesting = false; }); }
    }

    void launchScreenTest() async {
        final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const ScreenTestPage()));
        if (result == true) {
            safeSocketWrite("TEST_ECRAN_OK\n");
            setState(() { testsPassed['Écran'] = true; });
        } else {
            safeSocketWrite("TEST_ECRAN_FAIL\n");
        }
    }
    
    void launchButtonTest() async {
        final result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const ButtonTestPage()));
        String testName = 'Boutons Vol';
        if (result == true) {
            safeSocketWrite("TEST_BOUTONS_VOL_OK\n");
            setState(() { testsPassed[testName] = true; });
        } else {
             safeSocketWrite("TEST_BOUTONS_VOL_FAIL\n");
        }
    }
    
    void showMobileValidationDialog(String testName) {
        showDialog(
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
        ];

        return Scaffold(
            appBar: AppBar(title: const Text("SCtest Mobile Pro"), centerTitle: true, backgroundColor: Colors.transparent, elevation: 0),
            body: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                    children: [
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