import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../globals.dart';

class SensorTestPage extends StatefulWidget {
    final String sensorType;
    const SensorTestPage({super.key, required this.sensorType});
    @override
    State<SensorTestPage> createState() => _SensorTestPageState();
}

class _SensorTestPageState extends State<SensorTestPage> {
    static const platform = MethodChannel('com.example.sctest/native');
    bool success = false;

    @override
    void initState() {
        super.initState();
        startSensor();
        // On écoute le même canal natif
        onGlobalNativeEvent = handleSensorEvent;
    }
    
    @override
    void dispose() {
        platform.invokeMethod("stopSensor");
        onGlobalNativeEvent = null;
        super.dispose();
    }

    void startSensor() {
        platform.invokeMethod("startSensor", widget.sensorType);
    }

    void handleSensorEvent(String event) {
        if (!mounted || success) return;
        if (widget.sensorType == "ACCEL" && event == "SHAKE_DETECTED") validate();
        if (widget.sensorType == "PROXIMITY" && event == "PROXIMITY_NEAR") validate();
    }

    void validate() {
        setState(() { success = true; });
        HapticFeedback.heavyImpact();
        Future.delayed(const Duration(seconds: 1), () {
             if (mounted) Navigator.pop(context, true); 
        });
    }

    @override
    Widget build(BuildContext context) {
        bool isAccel = widget.sensorType == "ACCEL";
        return Scaffold(
            backgroundColor: success ? Colors.green : Colors.black,
            appBar: AppBar(title: Text(isAccel ? "Accéléromètre" : "Proximité"), automaticallyImplyLeading: false),
            body: Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                        Icon(isAccel ? Icons.vibration : Icons.sensors, size: 100, color: Colors.white),
                        const SizedBox(height: 20),
                        Text(isAccel ? "SECOUEZ LE TÉLÉPHONE" : "CACHEZ LE HAUT DE L'ÉCRAN", 
                             style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 50),
                        ElevatedButton(
                            onPressed: () => Navigator.pop(context, false),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            child: const Text("Abandonner")
                        )
                    ],
                ),
            ),
        );
    }
}