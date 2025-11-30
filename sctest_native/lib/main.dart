import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';

// Variable globale pour simplifier la communication des boutons
Function(String)? onGlobalButtonEvent;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        
        // ÉCOUTEUR PRINCIPAL: On reçoit le signal natif et on le passe à la fonction globale
        platform.setMethodCallHandler((call) async {
            if (call.method == "onButtonEvent") {
                if (onGlobalButtonEvent != null) {
                    onGlobalButtonEvent!(call.arguments as String);
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
        } catch (e) {
            safeSocketWrite("TEST_${commandName}_FAIL\n");
            setState(() { testsPassed[name] = false; audioStatusMessage = "Erreur $name: $e"; });
        } finally {
            setState(() { isAudioTesting = false; });
        }
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
                        TextButton(
                            onPressed: () {
                                String cleanedName = testName.toUpperCase().replaceAll(" ", "_").replaceAll("É", "E").replaceAll("(", "").replaceAll(")", "");
                                safeSocketWrite("TEST_${cleanedName}_OK\n");
                                setState(() { testsPassed[testName] = true; });
                                Navigator.of(context).pop();
                            },
                            child: const Text('✅ OUI', style: TextStyle(color: Colors.green)),
                        ),
                        TextButton(
                            onPressed: () {
                                String cleanedName = testName.toUpperCase().replaceAll(" ", "_").replaceAll("É", "E").replaceAll("(", "").replaceAll(")", "");
                                safeSocketWrite("TEST_${cleanedName}_FAIL\n");
                                setState(() { testsPassed[testName] = false; });
                                Navigator.of(context).pop();
                            },
                            child: const Text('❌ NON', style: TextStyle(color: Colors.red)),
                        ),
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
            {'icon': Icons.camera_alt, 'name': 'Caméra', 'action': (){}},
            {'icon': Icons.touch_app, 'name': 'Tactile', 'action': (){}},
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

// --- PAGE TEST ÉCRAN ---
class ScreenTestPage extends StatefulWidget {
  const ScreenTestPage({super.key});
  @override
  State<ScreenTestPage> createState() => _ScreenTestPageState();
}
class _ScreenTestPageState extends State<ScreenTestPage> {
  int colorIndex = 0;
  bool isTouchTest = false;
  final List<Color> testColors = [Colors.red, Colors.green, Colors.blue, Colors.white, Colors.black];
  final int rows = 16; final int cols = 9; Set<int> touchedIndices = {};
  void nextStep() { setState(() { if (colorIndex < testColors.length - 1) colorIndex++; else isTouchTest = true; }); }
  void onTouch(PointerEvent details, BuildContext context) {
    if (!isTouchTest) return;
    final RenderBox box = context.findRenderObject() as RenderBox;
    final size = box.size;
    final cellWidth = size.width / cols; final cellHeight = size.height / rows;
    int col = (details.localPosition.dx / cellWidth).floor(); int row = (details.localPosition.dy / cellHeight).floor();
    int index = row * cols + col;
    if (index >= 0 && index < rows * cols) {
      if (!touchedIndices.contains(index)) {
        setState(() { touchedIndices.add(index); });
        HapticFeedback.selectionClick();
        if (touchedIndices.length == rows * cols) {
          HapticFeedback.heavyImpact();
          Future.delayed(const Duration(milliseconds: 200), () { if (mounted) Navigator.pop(context, true); });
        }
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    return Scaffold(body: isTouchTest ? buildTouchGrid() : buildColorTest());
  }
  Widget buildColorTest() { return GestureDetector(onTap: nextStep, child: Container(width: double.infinity, height: double.infinity, color: testColors[colorIndex])); }
  Widget buildTouchGrid() {
    return Listener(onPointerMove: (e) => onTouch(e, context), onPointerDown: (e) => onTouch(e, context), child: Stack(children: [
      Column(children: List.generate(rows, (r) => Expanded(child: Row(children: List.generate(cols, (c) { int index = r * cols + c; bool isTouched = touchedIndices.contains(index); return Expanded(child: Container(margin: const EdgeInsets.all(0.5), decoration: BoxDecoration(color: isTouched ? Colors.green : Colors.transparent, border: Border.all(color: Colors.grey.withOpacity(0.2))))); }))))),
      if (touchedIndices.length < rows * cols) Center(child: IgnorePointer(child: Text("${((touchedIndices.length / (rows*cols))*100).toInt()}%", style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white24)))),
    ]));
  }
  @override
  void dispose() { SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge); super.dispose(); }
}

// --- PAGE TEST BOUTONS ---
class ButtonTestPage extends StatefulWidget {
  const ButtonTestPage({super.key});
  @override
  State<ButtonTestPage> createState() => _ButtonTestPageState();
}

class _ButtonTestPageState extends State<ButtonTestPage> {
    Map<String, bool> results = {'Volume Haut': false, 'Volume Bas': false};
    
    @override
    void initState() {
        super.initState();
        // On "branche" notre fonction de réception au fil rouge global
        onGlobalButtonEvent = handleNativeButton;
    }
    
    @override
    void dispose() {
        // On débranche le fil quand on quitte
        onGlobalButtonEvent = null;
        super.dispose();
    }

    void handleNativeButton(String event) {
        if (!mounted) return;
        if (event == 'VOLUME_UP') validateButton('Volume Haut');
        if (event == 'VOLUME_DOWN') validateButton('Volume Bas');
    }

    void validateButton(String keyName) {
        if (!results[keyName]!) {
            setState(() { results[keyName] = true; });
            if (results.values.every((r) => r)) {
                HapticFeedback.heavyImpact();
                Future.delayed(const Duration(milliseconds: 300), () { if (mounted) Navigator.pop(context, true); });
            }
        }
    }
    
    @override
    Widget build(BuildContext context) {
        return Scaffold(
            appBar: AppBar(title: const Text("Test Boutons Vol"), automaticallyImplyLeading: false),
            body: Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                        const Text("Appuyez sur les boutons de volume :", style: TextStyle(fontSize: 18, color: Colors.white70)),
                        const SizedBox(height: 30),
                        _buildButtonStatus("Volume Haut", results['Volume Haut']!),
                        const SizedBox(height: 20),
                        _buildButtonStatus("Volume Bas", results['Volume Bas']!),
                        const SizedBox(height: 20),
                        // CORRECTION ICI : Utilisation de styleFrom au lieu de fromStyle
                        ElevatedButton(
                            onPressed: () => Navigator.pop(context, false), 
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red), 
                            child: const Text("Abandonner")
                        ),
                    ],
                ),
            ),
        );
    }

    Widget _buildButtonStatus(String name, bool status) {
        return Container(
            width: 250, padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: status ? Colors.green.shade700 : Colors.grey.shade800, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
                    Icon(status ? Icons.check_circle : Icons.radio_button_unchecked, color: Colors.white),
                    const SizedBox(width: 10),
                    Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text(status ? "OK" : "...", style: TextStyle(color: status ? Colors.white : Colors.orangeAccent)),
            ]),
        );
    }
}