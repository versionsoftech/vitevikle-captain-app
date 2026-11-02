package com.vitecaptain.driver

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.PowerManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        val launch = intent?.action == Intent.ACTION_MAIN && intent.hasCategory(Intent.CATEGORY_LAUNCHER)
        if (launch && !isTaskRoot) {
            finish()
            return
        }
        stopService(Intent(this, OnDutyService::class.java))
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    override fun onPause() {
        if (leavingApp) appInForeground = false
        super.onPause()
        if (leavingApp) showPendingBubble()
    }

    override fun onUserLeaveHint() {
        leavingApp = true
        appInForeground = false
        super.onUserLeaveHint()
        showPendingBubble()
    }

    override fun onResume() {
        leavingApp = false
        appInForeground = true
        RideBubbleService.dismissedByUser = false
        stopService(Intent(this, RideBubbleService::class.java))
        super.onResume()
    }

    private var savedMusic = -1
    private var savedRing = -1
    private var savedAlarm = -1
    private var savedRinger = -1
    private var wakeLock: PowerManager.WakeLock? = null
    private var leavingApp = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "prepare" -> {
                        RideBubbleService.pending = payloadFrom(call)
                        result.success(true)
                    }
                    "start" -> {
                        val payload = payloadFrom(call)
                        RideBubbleService.pending = payload
                        if (RideBubbleService.dismissedByUser) {
                            result.success(false)
                        } else {
                            result.success(launchBubble(payload, null))
                        }
                    }
                    "move" -> {
                        val payload = payloadFrom(call)
                        RideBubbleService.pending = payload
                        if (appInForeground || RideBubbleService.dismissedByUser) {
                            result.success(false)
                        } else {
                            result.success(launchBubble(payload, "move"))
                        }
                    }
                    "stop" -> {
                        stopService(Intent(this, RideBubbleService::class.java))
                        result.success(true)
                    }
                    "clear" -> {
                        RideBubbleService.pending = null
                        RideBubbleService.dismissedByUser = false
                        stopService(Intent(this, RideBubbleService::class.java))
                        result.success(true)
                    }
                    "boostAlert" -> {
                        boostAlert()
                        result.success(true)
                    }
                    "restoreAlert" -> {
                        restoreAlert()
                        result.success(true)
                    }
                    "startOrderRing" -> {
                        OrderRingPlayer.start(this)
                        result.success(true)
                    }
                    "stopOrderRing" -> {
                        OrderRingPlayer.stop()
                        result.success(true)
                    }
                    "startDuty" -> {
                        stopService(Intent(this, OnDutyService::class.java))
                        DutyLock.acquire(this)
                        result.success(true)
                    }
                    "stopDuty" -> {
                        stopService(Intent(this, OnDutyService::class.java))
                        DutyLock.release()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun showPendingBubble() {
        val payload = RideBubbleService.pending ?: return
        if (RideBubbleService.dismissedByUser) return
        launchBubble(payload, null)
    }

    private fun launchBubble(payload: RideBubbleService.Payload, action: String?): Boolean {
        return try {
            ContextCompat.startForegroundService(this, payload.toIntent(this, action))
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun payloadFrom(call: MethodCall): RideBubbleService.Payload {
        fun num(key: String): Double {
            return when (val value = call.argument<Any>(key)) {
                is Double -> value
                is Float -> value.toDouble()
                is Int -> value.toDouble()
                is Long -> value.toDouble()
                is String -> value.toDoubleOrNull() ?: 0.0
                else -> 0.0
            }
        }
        return RideBubbleService.Payload(
            title = call.argument<String>("title") ?: "Ride in progress",
            body = call.argument<String>("body") ?: "",
            eta = call.argument<String>("eta") ?: "",
            lat = num("lat"),
            lng = num("lng"),
            targetLat = num("targetLat"),
            targetLng = num("targetLng"),
        )
    }

    private fun boostAlert() {
        try {
            val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (savedMusic < 0) {
                savedMusic = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
                savedRing = audio.getStreamVolume(AudioManager.STREAM_RING)
                savedAlarm = audio.getStreamVolume(AudioManager.STREAM_ALARM)
                savedRinger = audio.ringerMode
            }
            setMax(audio, AudioManager.STREAM_MUSIC)
            setMax(audio, AudioManager.STREAM_RING)
            setMax(audio, AudioManager.STREAM_ALARM)
            if (audio.ringerMode != AudioManager.RINGER_MODE_NORMAL) {
                try {
                    audio.ringerMode = AudioManager.RINGER_MODE_NORMAL
                } catch (_: Exception) {
                }
            }
            val power = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!power.isInteractive) {
                @Suppress("DEPRECATION")
                val lock = power.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                        PowerManager.ACQUIRE_CAUSES_WAKEUP or
                        PowerManager.ON_AFTER_RELEASE,
                    "vitevikle:ride_alert"
                )
                lock.acquire(20_000L)
                wakeLock = lock
            }
        } catch (_: Exception) {
        }
    }

    private fun restoreAlert() {
        try {
            val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (savedMusic >= 0) {
                audio.setStreamVolume(AudioManager.STREAM_MUSIC, savedMusic, 0)
                audio.setStreamVolume(AudioManager.STREAM_RING, savedRing.coerceAtLeast(0), 0)
                audio.setStreamVolume(AudioManager.STREAM_ALARM, savedAlarm.coerceAtLeast(0), 0)
                if (savedRinger >= 0) {
                    try {
                        audio.ringerMode = savedRinger
                    } catch (_: Exception) {
                    }
                }
            }
        } catch (_: Exception) {
        }
        savedMusic = -1
        savedRing = -1
        savedAlarm = -1
        savedRinger = -1
        val lock = wakeLock
        if (lock != null && lock.isHeld) {
            lock.release()
        }
        wakeLock = null
    }

    private fun setMax(audio: AudioManager, stream: Int) {
        try {
            audio.setStreamVolume(stream, audio.getStreamMaxVolume(stream), 0)
        } catch (_: Exception) {
        }
    }

    companion object {
        private const val CHANNEL = "com.vitecaptain.driver/ride_bubble"
        @Volatile var appInForeground = true
    }
}
