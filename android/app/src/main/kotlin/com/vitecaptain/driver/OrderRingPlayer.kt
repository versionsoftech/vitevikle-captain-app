package com.vitecaptain.driver

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.PowerManager

object OrderRingPlayer {
    private var player: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null

    fun start(context: Context) {
        val app = context.applicationContext
        raiseVolume(app)
        wakeScreen(app)
        if (player?.isPlaying == true) return
        stop()
        try {
            val mp = MediaPlayer()
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            val fd = app.resources.openRawResourceFd(R.raw.ride_alert)
            mp.setDataSource(fd.fileDescriptor, fd.startOffset, fd.length)
            fd.close()
            mp.setWakeMode(app, PowerManager.PARTIAL_WAKE_LOCK)
            mp.isLooping = true
            mp.setVolume(1f, 1f)
            mp.prepare()
            requestFocus(app)
            mp.start()
            player = mp
        } catch (_: Exception) {
        }
    }

    fun stop() {
        try {
            player?.stop()
        } catch (_: Exception) {
        }
        try {
            player?.release()
        } catch (_: Exception) {
        }
        player = null
        val lock = wakeLock
        if (lock != null && lock.isHeld) {
            lock.release()
        }
        wakeLock = null
    }

    private fun requestFocus(app: Context) {
        try {
            val audio = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build()
                    )
                    .build()
                audio.requestAudioFocus(request)
            } else {
                @Suppress("DEPRECATION")
                audio.requestAudioFocus(null, AudioManager.STREAM_ALARM, AudioManager.AUDIOFOCUS_GAIN)
            }
        } catch (_: Exception) {
        }
    }

    private fun raiseVolume(app: Context) {
        try {
            val audio = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            try {
                audio.ringerMode = AudioManager.RINGER_MODE_NORMAL
            } catch (_: Exception) {
            }
            for (stream in intArrayOf(AudioManager.STREAM_ALARM, AudioManager.STREAM_RING, AudioManager.STREAM_MUSIC)) {
                try {
                    audio.setStreamVolume(stream, audio.getStreamMaxVolume(stream), 0)
                } catch (_: Exception) {
                }
            }
        } catch (_: Exception) {
        }
    }

    private fun wakeScreen(app: Context) {
        try {
            val power = app.getSystemService(Context.POWER_SERVICE) as PowerManager
            if (power.isInteractive) return
            @Suppress("DEPRECATION")
            val lock = power.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                    PowerManager.ACQUIRE_CAUSES_WAKEUP or
                    PowerManager.ON_AFTER_RELEASE,
                "vitevikle:order_ring"
            )
            lock.acquire(20_000L)
            wakeLock = lock
        } catch (_: Exception) {
        }
    }
}
