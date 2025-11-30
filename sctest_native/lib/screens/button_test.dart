import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../globals.dart';

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
        // On branche notre fonction locale au fil rouge global
        onGlobalNativeEvent = handleNativeButton;
    }
    
    @override
    void dispose() {
        onGlobalNativeEvent = null; // On débranche
        super.dispose();
    }

    void handleNativeButton(String event) {
        if (!mounted) return;
        if (event == 'VOLUME_UP') validateButton('Volume Haut');
        if (event == 'VOLUME_DOWN') validateButton('Volume Bas');
    }

    void validateButton(String keyName) {
        if (!results[keyName]!) {
            setState(() {
                results[keyName] = true;
            });
            if (results.values.every((r) => r)) {
                HapticFeedback.heavyImpact();
                Future.delayed(const Duration(milliseconds: 300), () {
                    if (mounted) Navigator.pop(context, true); 
                });
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
            width: 250,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
                color: status ? Colors.green.shade700 : Colors.grey.shade800,
                borderRadius: BorderRadius.circular(10)
            ),
            child: Row(
                children: [
                    Icon(status ? Icons.check_circle : Icons.radio_button_unchecked, color: Colors.white),
                    const SizedBox(width: 10),
                    Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text(status ? "OK" : "...", style: TextStyle(color: status ? Colors.white : Colors.orangeAccent)),
                ],
            ),
        );
    }
}