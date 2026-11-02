package com.vitecaptain.driver

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

/// Keeps the driver process reachable while the screen is off so a new order can ring.
class OnDutyService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            releaseLock()
            stopSelf()
            return START_NOT_STICKY
        }
        startForeground(NOTICE_ID, buildNotice())
        holdLock()
        return START_STICKY
    }

    override fun onDestroy() {
        releaseLock()
        super.onDestroy()
    }

    private fun holdLock() {
        if (wakeLock?.isHeld == true) return
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        @Suppress("DEPRECATION")
        val lock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "vitevikle:on_duty")
        lock.setReferenceCounted(false)
        lock.acquire()
        wakeLock = lock
    }

    private fun releaseLock() {
        val lock = wakeLock
        if (lock != null && lock.isHeld) lock.release()
        wakeLock = null
    }

    private fun buildNotice(): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL, "On duty", NotificationManager.IMPORTANCE_LOW)
            manager.createNotificationChannel(channel)
        }
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("You are on duty")
            .setContentText("New rides will ring even if the screen is off")
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val CHANNEL = "vite_on_duty"
        private const val NOTICE_ID = 2408
        const val ACTION_STOP = "com.vitecaptain.driver.STOP_DUTY"
    }
}
