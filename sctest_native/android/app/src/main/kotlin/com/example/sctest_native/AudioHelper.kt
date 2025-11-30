package com.example.sctest_native

import android.content.Context
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.io.IOException

class AudioHelper(private val context: Context) {
    private var mediaRecorder: MediaRecorder? = null
    private var mediaPlayer: MediaPlayer? = null
    private var audioFilePath: String = ""
    
    private val AMPLITUDE_THRESHOLD = 5000 
    private val MONITORING_DURATION_MS = 3000L 

    private val handler = Handler(Looper.getMainLooper())
    private var runnable: Runnable? = null
    private var testResult: MethodChannel.Result? = null

    fun startMonitoringRecording(micType: String, result: MethodChannel.Result) {
        stopMonitoring()
        cleanupRecording()

        testResult = result
        audioFilePath = "${context.externalCacheDir?.absolutePath}/flutter_audio_test.3gp"
        
        mediaRecorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(context)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }
        
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
                testResult?.error("RECORD_FAIL", "Échec start", e.toString())
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

    fun cleanupRecording() {
        try { mediaRecorder?.apply { stop(); reset(); release() } } catch (e: Exception) {}
        mediaRecorder = null
    }

    fun playToneOnSpeaker(speakerType: String, result: MethodChannel.Result) {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
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
    
    fun destroy() {
        cleanupRecording()
        stopMonitoring()
        mediaPlayer?.release()
    }
}