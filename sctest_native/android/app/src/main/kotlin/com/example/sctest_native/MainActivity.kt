package com.example.sctest_native

import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Vibrator
import android.os.VibrationEffect
import android.view.KeyEvent 
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.sctest/native"
    private val REQUEST_RECORD_AUDIO_PERMISSION = 200 
    
    // LA CLÉ DU SUCCÈS : Une variable de classe accessible partout
    private lateinit var methodChannel: MethodChannel

    private var resultCallback: MethodChannel.Result? = null 
    private var mediaRecorder: MediaRecorder? = null
    private var mediaPlayer: MediaPlayer? = null
    private var audioFilePath: String = ""
    private val handler = Handler(Looper.getMainLooper())
    private var runnable: Runnable? = null
    private var testResult: MethodChannel.Result? = null
    private val AMPLITUDE_THRESHOLD = 5000 
    private val MONITORING_DURATION_MS = 3000L 

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // INITIALISATION UNIQUE
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
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
                "startMonitoringRecording" -> {
                    val micType = call.arguments as String 
                    startMonitoringRecording(micType, result)
                }
                "playToneOnSpeaker" -> {
                    val speakerType = call.arguments as String 
                    playToneOnSpeaker(speakerType, result)
                }
                else -> result.notImplemented()
            }
        }
    }
    
    // --- INTERCEPTION DES BOUTONS (CORRIGÉE) ---
    
    // 1. Bloquer le menu volume système
    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            return true // On dit à Android "J'ai géré le clic, n'affiche pas la barre de volume"
        }
        return super.onKeyDown(keyCode, event)
    }

    // 2. Envoyer l'info à Flutter (SANS ERREUR DE TYPE)
    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
            // On utilise la variable initialisée plus haut. Plus de "?." ou de "!!" risqué.
            methodChannel.invokeMethod("onButtonEvent", "VOLUME_UP")
            return true
        }
        if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            methodChannel.invokeMethod("onButtonEvent", "VOLUME_DOWN")
            return true
        }
        return super.onKeyUp(keyCode, event)
    }

    // --- LE RESTE DU CODE (AUDIO/FLASH) NE CHANGE PAS ---
    
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_RECORD_AUDIO_PERMISSION) {
            val isGranted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            resultCallback?.success(isGranted)
            resultCallback = null 
        }
    }
    
    private fun requestMicPermission(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(this, android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            result.success(true) 
            return
        }
        resultCallback = result
        ActivityCompat.requestPermissions(this, arrayOf(android.Manifest.permission.RECORD_AUDIO, android.Manifest.permission.WRITE_EXTERNAL_STORAGE), REQUEST_RECORD_AUDIO_PERMISSION)
    }

    private fun startMonitoringRecording(micType: String, result: MethodChannel.Result) {
        stopMonitoring()
        cleanupRecording()
        testResult = result
        audioFilePath = "${externalCacheDir?.absolutePath}/flutter_audio_test.3gp"
        mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(this) else MediaRecorder()
        
        mediaRecorder?.apply {
            setAudioSource(when (micType) {
                "FRONT" -> MediaRecorder.AudioSource.MIC 
                "BACK" -> MediaRecorder.AudioSource.CAMCORDER 
                else -> MediaRecorder.AudioSource.MIC 
            })
            setOutputFormat(MediaRecorder.OutputFormat.THREE_GPP)
            setAudioEncoder(MediaRecorder.AudioEncoder.AMR_NB)
            setOutputFile(audioFilePath)
            try {
                prepare()
                start()
                handler.postDelayed({ startAmplitudeMonitoring() }, 500)
            } catch (e: IOException) {
                cleanupRecording()
                testResult?.error("RECORD_FAIL", "Erreur Start", e.toString())
                testResult = null
            }
        }
    }
    
    private fun startAmplitudeMonitoring() {
        var monitoringTime = 0L
        runnable = object : Runnable {
            override fun run() {
                if (testResult == null) return
                val amplitude = mediaRecorder?.maxAmplitude ?: 0
                if (amplitude > AMPLITUDE_THRESHOLD) {
                    stopMonitoring()
                    cleanupRecording()
                    testResult?.success(true) 
                    testResult = null
                    return
                }
                monitoringTime += 200L 
                if (monitoringTime >= MONITORING_DURATION_MS) {
                    stopMonitoring()
                    cleanupRecording()
                    testResult?.success(false) 
                    testResult = null
                    return
                }
                handler.postDelayed(this, 200)
            }
        }
        handler.post(runnable!!)
    }
    
    private fun stopMonitoring() {
        runnable?.let { handler.removeCallbacks(it) }
        runnable = null
    }

    private fun cleanupRecording() {
        try { mediaRecorder?.apply { stop(); reset(); release() } } catch (e: Exception) {}
        mediaRecorder = null
    }

    private fun playToneOnSpeaker(speakerType: String, result: MethodChannel.Result) {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val toneGen = ToneGenerator(AudioManager.STREAM_MUSIC, 100) 
        try {
            when (speakerType) {
                "EARPIECE" -> {
                    audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                    audioManager.isSpeakerphoneOn = false 
                    toneGen.startTone(ToneGenerator.TONE_DTMF_P, 1000) 
                }
                "MEDIA" -> {
                    audioManager.mode = AudioManager.MODE_NORMAL
                    audioManager.isSpeakerphoneOn = true 
                    toneGen.startTone(ToneGenerator.TONE_DTMF_3, 1000) 
                }
            }
            Handler(Looper.getMainLooper()).postDelayed({
                toneGen.release()
                audioManager.mode = AudioManager.MODE_NORMAL
                audioManager.isSpeakerphoneOn = false
                result.success(true)
            }, 1200) 
        } catch (e: Exception) {
            result.error("SETUP_FAIL", "Erreur Audio", e.toString())
        }
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
        cleanupRecording()
        stopMonitoring()
        mediaPlayer?.release()
    }
}