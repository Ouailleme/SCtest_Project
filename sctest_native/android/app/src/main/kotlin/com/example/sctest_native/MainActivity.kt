package com.example.sctest_native

import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.camera2.CameraManager
import android.os.Build
import android.os.Vibrator
import android.os.VibrationEffect
import android.view.KeyEvent 
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.lang.Math.sqrt

class MainActivity: FlutterActivity(), SensorEventListener {
    private val CHANNEL = "com.example.sctest/native"
    private val REQUEST_RECORD_AUDIO_PERMISSION = 200 
    
    private lateinit var methodChannel: MethodChannel
    private lateinit var sensorManager: SensorManager
    private lateinit var audioHelper: AudioHelper
    
    private var currentSensorTest: String? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger!!, CHANNEL)
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        audioHelper = AudioHelper(this)
        
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startSensor" -> {
                    val type = call.arguments as String
                    startSensorTest(type)
                    result.success(true)
                }
                "stopSensor" -> {
                    stopSensorTest()
                    result.success(true)
                }
                
                "startMonitoringRecording" -> audioHelper.startMonitoringRecording(call.arguments as String, result)
                "playToneOnSpeaker" -> audioHelper.playToneOnSpeaker(call.arguments as String, result)
                "requestMicPermission" -> requestMicPermission(result)

                "toggleFlash" -> {
                    val turnOn = call.arguments as Boolean
                    toggleFlash(turnOn)
                    result.success(true)
                }
                "vibrate" -> {
                    vibratePhone()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
    
    private fun startSensorTest(type: String) {
        stopSensorTest()
        currentSensorTest = type
        if (type == "ACCEL") {
            sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)?.let { 
                sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_UI) 
            }
        } else if (type == "PROXIMITY") {
            sensorManager.getDefaultSensor(Sensor.TYPE_PROXIMITY)?.let { 
                sensorManager.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL) 
            }
        }
    }

    private fun stopSensorTest() {
        sensorManager.unregisterListener(this)
        currentSensorTest = null
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null) return
        if (currentSensorTest == "ACCEL") {
            val acceleration = sqrt((event.values[0]*event.values[0] + event.values[1]*event.values[1] + event.values[2]*event.values[2]).toDouble())
            if (acceleration > 15) {
                methodChannel.invokeMethod("onButtonEvent", "SHAKE_DETECTED")
                stopSensorTest()
            }
        } else if (currentSensorTest == "PROXIMITY") {
            if (event.values[0] < 1.0) {
                methodChannel.invokeMethod("onButtonEvent", "PROXIMITY_NEAR")
                stopSensorTest()
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) return true 
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
            methodChannel.invokeMethod("onButtonEvent", "VOLUME_UP")
            return true
        }
        if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            methodChannel.invokeMethod("onButtonEvent", "VOLUME_DOWN")
            return true
        }
        return super.onKeyUp(keyCode, event)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_RECORD_AUDIO_PERMISSION) {
            // Gestion basique, la vraie logique est déléguée si nécessaire
        }
    }
    
    private fun requestMicPermission(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            result.success(true) 
            return
        }
        ActivityCompat.requestPermissions(this, arrayOf(android.Manifest.permission.RECORD_AUDIO, android.Manifest.permission.WRITE_EXTERNAL_STORAGE), REQUEST_RECORD_AUDIO_PERMISSION)
        result.success(false) // On attend le callback système
    }

    private fun toggleFlash(status: Boolean) { 
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager
                val cameraId = cameraManager.cameraIdList[0]
                cameraManager.setTorchMode(cameraId, status)
            } catch (e: Exception) {}
        }
    }
    
    private fun vibratePhone() {
        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        if (Build.VERSION.SDK_INT >= 26) {
            vibrator.vibrate(VibrationEffect.createOneShot(500, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(500)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        audioHelper.destroy()
    }
}